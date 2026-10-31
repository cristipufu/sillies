import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

private func attachmentRecord() -> SessionRecord {
  var record = SessionRecord(
    kind: .snap,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Fixture")),
    metadata: .init(createdAt: Date(timeIntervalSince1970: 1_000)))
  record.imageFilename = "saved.png"
  return record
}

@Test func failedVaultIndexCommitPreservesReferencedAttachmentsAndCanRetry() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { cleanCommitFixture(directory) }
  let files = VaultFileStorage(directory: directory)
  let record = attachmentRecord()
  let database = try VaultDatabase(directory: directory)
  try database.commit(
    .init(
      records: [.insert(record)], attachments: [.init(filename: "saved.png", data: Data([1, 2]))]))
  try database.sql.execute(
    "CREATE TRIGGER refuse_delete BEFORE DELETE ON records BEGIN SELECT RAISE(ABORT, 'injected failure'); END"
  )
  #expect(throws: (any Error).self) { try database.commit(.init(deletion: .all)) }
  #expect(try database.record(id: record.id) == record)
  #expect(try Data(contentsOf: files.attachmentURL(for: "saved.png")) == Data([1, 2]))
  try database.sql.execute("DROP TRIGGER refuse_delete")
  try database.commit(.init(deletion: .all))
  #expect(!FileManager.default.fileExists(atPath: try files.attachmentURL(for: "saved.png").path))
}

@Test func vaultStartupFinishesOnlyJournaledUnreferencedAttachmentCleanup() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { cleanCommitFixture(directory) }
  let files = VaultFileStorage(directory: directory)
  let record = attachmentRecord()
  let database = try VaultDatabase(directory: directory)
  try database.commit(.init(records: [.insert(record)]))
  for name in ["saved.png", "retired.m4a", "unrelated.txt"] {
    try files.write(Data([1]), named: name)
  }
  try database.stageCleanup("saved.png")
  try database.stageCleanup("retired.m4a")
  _ = try VaultDatabase(directory: directory)
  #expect(FileManager.default.fileExists(atPath: try files.url(for: "saved.png").path))
  #expect(FileManager.default.fileExists(atPath: try files.url(for: "unrelated.txt").path))
  #expect(!FileManager.default.fileExists(atPath: try files.url(for: "retired.m4a").path))
  #expect(throws: (any Error).self) { try files.attachmentURL(for: VaultDatabase.filename) }
}

@Test func failedRecordUpdateRollsBackSearchAlongWithItsBody() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { cleanCommitFixture(directory) }
  let database = try VaultDatabase(directory: directory)
  var record = attachmentRecord()
  record.transcript = "original searchable words"
  try database.commit(.init(records: [.insert(record)]))
  try database.sql.execute(
    "CREATE TRIGGER refuse_update BEFORE UPDATE ON records BEGIN SELECT RAISE(ABORT, 'injected failure'); END"
  )
  var changed = record
  changed.transcript = "replacement words"
  #expect(throws: (any Error).self) { try database.commit(.init(records: [.update(changed)])) }
  #expect(try database.record(id: record.id) == record)
  #expect(try database.page(.init(search: .init(kind: nil, query: "original"))).total == 1)
  #expect(try database.page(.init(search: .init(kind: nil, query: "replacement"))).total == 0)
}

private func cleanCommitFixture(_ directory: URL) {
  do { try FileManager.default.removeItem(at: directory) } catch {
    Issue.record("Fixture cleanup failed: \(error)")
  }
}

@Test func vaultMissingUpdateInvalidatesOptimisticDetailsWithoutResurrectingData() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { cleanCommitFixture(directory) }
  let database = try VaultDatabase(directory: directory)
  let record = attachmentRecord()
  try database.commit(.init(records: [.insert(record)]))
  try database.commit(.init(deletion: .records([record.id])))
  let invalidated = try database.commit(.init(records: [.update(record)]))
  #expect(invalidated == [record.id])
  #expect(try database.record(id: record.id) == nil)
  #expect(try database.page(.init()).records.isEmpty)
}
