import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func relevanceMetadataIndexPreservesEveryPageAndFilter() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  let records = (0..<230).map { index in
    SessionRecord(
      kind: index.isMultiple(of: 2) ? .record : .stash,
      origin: .init(
        characterID: "pogo", characterName: "Pogo", source: .init(appName: "Source \(index % 3)")),
      content: .init(text: .init(transcript: "Meeting agenda and decision \(index).")),
      metadata: .init(createdAt: Date(timeIntervalSince1970: Double(index))))
  }
  try database.commit(.init(records: records.map(VaultRecordWrite.insert)))
  for (index, record) in records.enumerated() {
    if index.isMultiple(of: 5) {
      try database.editDocument(id: record.id, edit: .star, at: Date())
    }
    if index.isMultiple(of: 7) {
      try database.editDocument(id: record.id, edit: .moveToTrash, at: Date())
    }
    if index.isMultiple(of: 11) {
      try database.editDocument(id: record.id, edit: .tags(["project"]), at: Date())
    }
  }
  try database.commit(.init(deletion: .records([records[1].id])))
  var queries = [VaultWorkspaceQuery.Scope.all, .starred, .meetings, .trash].map {
    VaultWorkspaceQuery(scope: $0, text: "meeting", ordering: .relevance)
  }
  var tagged = VaultWorkspaceQuery(text: "meeting", ordering: .relevance)
  tagged.tag = "project"
  queries.append(tagged)
  var dated = VaultWorkspaceQuery(text: "meeting", ordering: .relevance)
  dated.from = Date(timeIntervalSince1970: 45)
  dated.until = Date(timeIntervalSince1970: 130)
  queries.append(dated)
  let indexed = try queries.map { try allMatches(database, query: $0) }
  try database.sql.execute("DROP VIEW available_search_records")
  try database.sql.execute(
    "CREATE VIEW available_search_records AS SELECT * FROM available_records")
  let ordinary = try queries.map { try allMatches(database, query: $0) }
  #expect(indexed == ordinary)
  #expect(database.metrics.loadedBodies == 0)
}

@Test func relevanceFilteringUsesCoveringMetadataAndSharesCleanupVisibility() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  var plan: [String] = []
  try database.sql.rows(
    "EXPLAIN QUERY PLAN SELECT id,created,kind,protected,modified,image FROM available_search_records WHERE id=?",
    [.text(UUID().uuidString)]
  ) { row in plan.append(try VaultSQLConnection.text(row, column: 3)) }
  #expect(plan.contains { $0.contains("COVERING INDEX records_search_metadata") })
  let record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
    content: .init(text: .init(transcript: "Searchable meeting")))
  try database.commit(.init(records: [.insert(record)]))
  try database.commit(.init(deletion: .all))
  #expect(try database.sql.integer("SELECT count(*) FROM available_search_records") == 0)
  try database.commit(.init(records: [.insert(record)]))
  #expect(try database.sql.integer("SELECT count(*) FROM available_search_records") == 1)
  #expect(
    try database.workspacePage(.init(text: "meeting", ordering: .relevance)).records.count == 1)
}

@Test func versionThreeVaultAddsSearchMetadataWithoutChangingContent() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  let record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
    content: .init(text: .init(transcript: "Preserved source")))
  try database.commit(.init(records: [.insert(record)]))
  try database.sql.execute("DROP VIEW available_search_records")
  try database.sql.execute("DROP INDEX records_search_metadata")
  try database.sql.execute("DROP INDEX records_backup_files")
  try database.sql.execute("DROP INDEX workspace_backup_previews")
  try database.sql.execute("PRAGMA user_version=3")
  let migrated = try VaultDatabase(directory: directory)
  #expect(try migrated.sql.integer("PRAGMA user_version") == 4)
  #expect(try migrated.record(id: record.id)?.transcript == record.transcript)
  #expect(
    try migrated.workspacePage(.init(text: "preserved", ordering: .relevance)).records.map(\.id)
      == [record.id])
}

private func allMatches(_ database: VaultDatabase, query: VaultWorkspaceQuery) throws -> [String] {
  var result: [String] = []
  var cursor: VaultWorkspaceCursor?
  repeat {
    let page = try database.workspacePage(query, after: cursor)
    result += page.records.map { "\($0.id)|\($0.excerpt)|\(String(describing: $0.match))" }
    cursor = page.next
  } while cursor != nil
  return result
}

@Test func relevanceStreamingPreservesMaterializedRanksAndBestBlocksAcrossPages() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  for index in 0..<215 {
    let record = SessionRecord(
      kind: .record,
      origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
      content: .init(
        text: .init(
          transcript: String(repeating: "Meeting detail \(index). ", count: index % 9 + 1)),
        notes: .init(summary: index.isMultiple(of: 3) ? "Meeting meeting" : "Other summary")))
    try database.commit(.init(records: [.insert(record)]))
  }
  var expected: [String] = []
  try database.sql.rows(
    """
    WITH scored AS MATERIALIZED (
      SELECT rowid AS block_id,rank AS relevance FROM content_search WHERE content_search MATCH '"meeting"*'),
    documents AS (
      SELECT b.record_id,min(s.relevance) AS score,b.id AS block_id
      FROM scored s JOIN content_blocks b ON b.id=s.block_id GROUP BY b.record_id)
    SELECT d.record_id,b.section,b.ordinal FROM documents d JOIN content_blocks b ON b.id=d.block_id
    ORDER BY d.score,d.record_id
    """
  ) { row in
    expected.append(
      try (0...2).map { try VaultSQLConnection.text(row, column: Int32($0)) }.joined(separator: "|")
    )
  }
  var actual: [String] = []
  var cursor: VaultWorkspaceCursor?
  repeat {
    let page = try database.workspacePage(
      .init(text: "meeting", ordering: .relevance), after: cursor)
    actual += try page.records.map { header in
      let match = try #require(header.match)
      return "\(header.id)|\(match.section.rawValue)|\(match.ordinal)"
    }
    cursor = page.next
  } while cursor != nil
  #expect(actual == expected)
}
