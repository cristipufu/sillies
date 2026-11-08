import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func rankBoundaryPreservesLateBetterMatchesAndIdentifierTies() throws {
  let fixture = try RankBoundaryFixture()
  defer { fixture.remove() }
  let records = try (1...2_200).reversed().map { try fixture.record($0) }
  try fixture.database.commit(.init(records: records.map(VaultRecordWrite.insert)))
  var strongest = try fixture.record(2_201, text: "Harbor meeting harbor meeting harbor meeting")
  strongest.summary = "Harbor meeting plans and the weekly project review"
  try fixture.database.commit(.init(records: [.insert(strongest)]))
  // Each record has two matching sections; the last identities and strongest result are outside
  // the preparation sample. They must still be considered, with their best passage and score.
  for matching in [VaultTextMatching.words, .phrase, .literal] {
    var query = VaultWorkspaceQuery(text: "harbor meeting", ordering: .relevance)
    query.textMatching = matching
    let plan = try #require(try VaultTextSearchPlan(query))
    #expect(try fixture.database.firstPageRankBoundary(plan, filter: .init(query)) != nil)
    let expected = try fixture.reference(query)
    #expect(expected.first?.id == strongest.id.uuidString)
    let first = try fixture.database.workspacePage(query)
    try fixture.expectPage(first, matches: Array(expected.prefix(100)))
    #expect(first.records.contains { $0.id == records.last?.id })
    let cursor = try #require(first.next)
    #expect(cursor.value == expected[99].score)
    let second = try fixture.database.workspacePage(query, after: cursor)
    try fixture.expectPage(second, matches: Array(expected.dropFirst(100).prefix(100)))
  }
  #expect(fixture.database.metrics.loadedBodies == 0)
}

@Test func rankBoundaryUsesTheSameEligibilityAsTheFinalSearch() throws {
  let fixture = try RankBoundaryFixture()
  defer { fixture.remove() }
  let records = try (1...320).map { try fixture.record($0) }
  try fixture.database.commit(.init(records: records.map(VaultRecordWrite.insert)))
  let collection = VaultCollection(id: UUID(), name: "Project")
  try fixture.database.saveCollection(collection)
  for (index, record) in records.enumerated() {
    if index < 150 {
      try fixture.database.editDocument(id: record.id, edit: .moveToTrash, at: Date())
    } else {
      try fixture.database.editDocument(id: record.id, edit: .star, at: Date())
      try fixture.database.editDocument(id: record.id, edit: .tags(["project"]), at: Date())
      try fixture.database.editDocument(
        id: record.id, edit: .addToCollection(collection.id), at: Date())
    }
  }
  var queries = [VaultWorkspaceQuery.Scope.all, .trash, .starred, .meetings].map {
    VaultWorkspaceQuery(scope: $0, text: "meeting", ordering: .relevance)
  }
  var tagged = queries[0]
  tagged.tag = "project"
  queries.append(tagged)
  var collected = queries[0]
  collected.collectionID = collection.id
  queries.append(collected)
  var dated = queries[0]
  dated.from = Date(timeIntervalSince1970: 200)
  dated.until = Date(timeIntervalSince1970: 310)
  queries.append(dated)
  var sourced = queries[0]
  sourced.source = .init(appName: "Fixture", companionID: "pogo")
  queries.append(sourced)
  var absent = queries[0]
  absent.tag = "missing"
  queries.append(absent)
  for query in queries {
    let expected = try fixture.reference(query)
    let page = try fixture.database.workspacePage(query)
    try fixture.expectPage(page, matches: Array(expected.prefix(100)))
    if let cursor = page.next {
      #expect(cursor.value == expected[99].score)
      let second = try fixture.database.workspacePage(query, after: cursor)
      try fixture.expectPage(second, matches: Array(expected.dropFirst(100).prefix(100)))
    }
  }
}

@Test func rankBoundaryFallsBackWhenOneDocumentOccupiesTheSample() throws {
  let fixture = try RankBoundaryFixture()
  defer { fixture.remove() }
  let long = try fixture.record(10_000)
  try fixture.database.commit(.init(records: [.insert(long)]))
  // Construct a many-block document without allocating a meeting-sized body in the test host.
  // The production block triggers maintain the real FTS input for all inserted passages.
  try fixture.database.sql.execute(
    """
    WITH RECURSIVE ordinals(value) AS (
      SELECT 0 UNION ALL SELECT value+1 FROM ordinals WHERE value<4_200)
    INSERT INTO content_blocks(record_id,section,ordinal,text)
    SELECT ?,'notes',value,'Harbor meeting notes' FROM ordinals
    """, [.text(long.id.uuidString)])
  let later = try (1...110).map { try fixture.record($0) }
  try fixture.database.commit(.init(records: later.map(VaultRecordWrite.insert)))
  let query = VaultWorkspaceQuery(text: "meeting", ordering: .relevance)
  let plan = try #require(try VaultTextSearchPlan(query))
  #expect(try fixture.database.firstPageRankBoundary(plan, filter: .init(query)) == nil)
  let expected = try fixture.reference(query)
  try fixture.expectPage(
    fixture.database.workspacePage(query), matches: Array(expected.prefix(100)))
}

@Test func rankBoundaryExcludesRecordsWaitingForPhysicalCleanup() throws {
  let fixture = try RankBoundaryFixture()
  defer { fixture.remove() }
  let old = try (1...300).map { try fixture.record($0) }
  try fixture.database.commit(.init(records: old.map(VaultRecordWrite.insert)))
  try fixture.database.commit(.init(deletion: .all))
  let current = try (1_001...1_130).map { try fixture.record($0) }
  try fixture.database.commit(.init(records: current.map(VaultRecordWrite.insert)))
  #expect(try fixture.database.sql.integer("SELECT count(*) FROM records") > current.count)
  let query = VaultWorkspaceQuery(text: "meeting", ordering: .relevance)
  let expected = try fixture.reference(query)
  #expect(expected.count == current.count)
  let page = try fixture.database.workspacePage(query)
  try fixture.expectPage(page, matches: Array(expected.prefix(100)))
  #expect(page.next?.value == expected[99].score)
}

private struct RankBoundaryFixture {
  let directory: URL
  let database: VaultDatabase

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    database = try VaultDatabase(directory: directory)
  }
  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
  func record(_ identity: Int, text: String = "Harbor meeting plans and the weekly project review")
    throws -> SessionRecord
  {
    let suffix = String(format: "%012llX", Int64(identity))
    let id = try #require(UUID(uuidString: "00000000-0000-4000-8000-" + suffix))
    return .init(
      kind: .record,
      origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
      content: .init(text: .init(transcript: text), notes: .init(summary: text)),
      metadata: .init(id: id, createdAt: Date(timeIntervalSince1970: Double(identity))))
  }
  struct ReferenceMatch {
    let id: String
    let score: Double
    let section: String
    let ordinal: Int
  }
  func reference(_ query: VaultWorkspaceQuery) throws -> [ReferenceMatch] {
    let plan = try #require(try VaultTextSearchPlan(query))
    let filter = VaultWorkspaceFilter(query)
    var result: [ReferenceMatch] = []
    // Independent oracle: materialize and group every matching passage, without preparation,
    // thresholds or a result limit. Never derive expectations from the optimized query.
    try database.sql.rows(
      """
      WITH scores AS MATERIALIZED (
        SELECT rowid AS block_id,rank AS score FROM \(plan.table) WHERE \(plan.table) MATCH ?),
      documents AS (
        SELECT b.record_id,min(s.score) AS score,b.id AS block_id
        FROM scores s JOIN content_blocks b ON b.id=s.block_id GROUP BY b.record_id)
      SELECT d.record_id,d.score,b.section,b.ordinal FROM documents d
      JOIN available_records r ON r.id=d.record_id LEFT JOIN workspace w ON w.record_id=r.id
      JOIN content_blocks b ON b.id=d.block_id WHERE \(filter.sql) ORDER BY d.score,d.record_id
      """, [.text(plan.expression)] + filter.values
    ) { row in
      result.append(
        .init(
          id: try VaultSQLConnection.text(row), score: try VaultSQLConnection.real(row, column: 1),
          section: try VaultSQLConnection.text(row, column: 2),
          ordinal: try #require(Int(VaultSQLConnection.text(row, column: 3)))))
    }
    return result
  }
  func expectPage(_ page: VaultWorkspacePage, matches: [ReferenceMatch]) throws {
    #expect(page.records.map { $0.id.uuidString } == matches.map(\.id))
    for (header, expected) in zip(page.records, matches) {
      let location = try #require(header.match)
      #expect(location.section.rawValue == expected.section)
      #expect(location.ordinal == expected.ordinal)
    }
  }
}
