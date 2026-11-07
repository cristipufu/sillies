import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func backupReferenceBatchesSkipEmptyRecordsAndIncludeEveryFileInTrash() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  var expected: Set<String> = []
  for index in 0..<400 {
    var record = SessionRecord(
      kind: .stash,
      origin: .init(characterID: "vault", characterName: "", source: .init(appName: "Fixture")))
    if index.isMultiple(of: 2) {
      record.imageFilename = "image-\(index).png"
      record.audioFilename = "audio-\(index).wav"
      expected.formUnion(["image-\(index).png", "audio-\(index).wav"])
    }
    var metadata = VaultDocumentMetadata(kind: .link, title: "Link", modifiedAt: Date())
    if index.isMultiple(of: 3) {
      var link = try VaultLink(url: #require(URL(string: "https://example.com/item")))
      link.imageFilename = "preview-\(index).png"
      metadata.link = link
      expected.insert("preview-\(index).png")
    }
    metadata.trashedAt = .distantPast
    _ = try database.createDocument(record: record, metadata: metadata)
  }
  var names: Set<String> = []
  var position: UUID?
  var batches = 0
  while let batch = try database.backupAttachments(after: position) {
    #expect(batch.lastRecordID.uuidString > (position?.uuidString ?? ""))
    #expect(batch.filenames.count <= 128 * 3)
    position = batch.lastRecordID
    names.formUnion(batch.filenames)
    batches += 1
    #expect(batches < 5)
  }
  #expect(batches == 3)
  #expect(names == expected)
  #expect(database.metrics.loadedBodies == 0)
  var plan: [String] = []
  try database.sql.rows(
    "EXPLAIN QUERY PLAN " + database.backupAttachmentQuery,
    [.text(""), .text(""), .integer(128)]
  ) { row in
    plan.append(try VaultSQLConnection.text(row, column: 3))
  }
  #expect(plan.contains { $0.contains("MERGE (UNION ALL)") })
  #expect(!plan.contains { $0.contains("TEMP B-TREE") || $0.contains("records_audio") })
}

@Test func previousWorkspaceBackupRemainsReadableBeforeMigration() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  var record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
    content: .init(text: .init(transcript: "Preserved meeting")))
  record.audioFilename = "recording.wav"
  try database.commit(.init(records: [.insert(record)]))
  try database.sql.execute("DROP VIEW available_search_records")
  try database.sql.execute("DROP INDEX records_search_metadata")
  try database.sql.execute("DROP INDEX records_backup_files")
  try database.sql.execute("DROP INDEX workspace_backup_previews")
  try database.sql.execute("PRAGMA user_version=3")
  let snapshot = try VaultDatabase(reading: directory)
  #expect(try snapshot.backupAttachments(after: nil)?.filenames == ["recording.wav"])
  #expect(
    try snapshot.workspacePage(.init(text: "preserved", ordering: .relevance)).records.map(\.id)
      == [record.id])
  #expect(try snapshot.sql.integer("PRAGMA user_version") == 3)
}

@Test func backupReferenceCursorRejectsNoncanonicalStoredIDs() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  var record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
    metadata: .init(id: try #require(UUID(uuidString: "ABCDEFAB-1234-1234-1234-ABCDEFABCDEF"))))
  record.audioFilename = "recording.wav"
  try database.commit(.init(records: [.insert(record)]))
  // Simulate damaged external storage: converting this cursor back to uppercase would revisit it.
  try database.sql.execute("PRAGMA foreign_keys=OFF")
  try database.sql.execute("UPDATE records SET id=lower(id)")
  #expect(throws: CocoaError.self) { try database.backupAttachments(after: nil) }
}
