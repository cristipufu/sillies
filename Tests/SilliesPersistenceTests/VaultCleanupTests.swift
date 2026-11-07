import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func pendingDeletionIsHiddenImmediatelyAndLongContentIsReclaimedInSlices() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { cleanCleanupFixture(directory) }
  let database = try VaultDatabase(directory: directory)
  var record = cleanupRecord(1)
  record.transcript = String(repeating: "archived passage ", count: 100_000)
  record.audioFilename = "recording.m4a"
  try database.commit(
    .init(
      records: [.insert(record)], attachments: [.init(filename: "recording.m4a", data: Data([1]))]))
  let blockCount = try database.sql.integer("SELECT count(*) FROM content_blocks")
  try database.commit(.init(deletion: .records([record.id])))
  #expect(
    try database.sql.integer("SELECT count(*) FROM content_blocks") == blockCount
      - VaultDatabase.cleanupBlockLimit)
  #expect(try database.record(id: record.id) == nil)
  #expect(try database.documentHeader(id: record.id) == nil)
  #expect(try database.sectionPage(.init(recordID: record.id, section: .transcript)).blocks.isEmpty)
  #expect(try database.workspacePage(.init(text: "passage")).records.isEmpty)
  #expect(try database.pendingPassage() == nil)
  #expect(try database.cleanupProgress().isPending)
  #expect(
    FileManager.default.fileExists(atPath: directory.appendingPathComponent("recording.m4a").path))

  let reopened = try VaultDatabase(directory: directory)
  try drainCleanup(reopened)
  #expect(try reopened.sql.integer("SELECT count(*) FROM records") == 0)
  #expect(try reopened.sql.integer("SELECT count(*) FROM content_blocks") == 0)
  #expect(
    !FileManager.default.fileExists(atPath: directory.appendingPathComponent("recording.m4a").path))
}

@Test func clearAllUsesADurableCutoffAndPreservesSubsequentCaptures() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { cleanCleanupFixture(directory) }
  let database = try VaultDatabase(directory: directory)
  let originals = (0..<250).map(cleanupRecord)
  try database.commit(.init(records: originals.map(VaultRecordWrite.insert)))
  try database.commit(.init(deletion: .all))
  #expect(try database.sql.integer("SELECT count(*) FROM records") > 0)
  #expect(try database.page(.init()).total == 0)
  #expect(try database.workspacePage(.init(text: "capture")).records.isEmpty)
  let new = cleanupRecord(-100)
  try database.commit(.init(records: [.insert(new)]))
  let reopened = try VaultDatabase(directory: directory)
  #expect(try reopened.page(.init()).records.map(\.id) == [new.id])
  #expect(try reopened.workspacePage(.init()).records.map(\.id) == [new.id])
  #expect(try reopened.workspacePage(.init(text: "capture")).records.map(\.id) == [new.id])
  try drainCleanup(reopened)
  #expect(try reopened.identifiers() == [new.id])
  #expect(try reopened.sql.integer("SELECT count(*) FROM search_index_content") > 0)
}

@Test func retentionAndTrashJobsResumeWithoutDeletingKeptOrNewlyTrashedItems() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { cleanCleanupFixture(directory) }
  let database = try VaultDatabase(directory: directory)
  let originals = (0..<450).map(cleanupRecord)
  try database.commit(.init(records: originals.map(VaultRecordWrite.insert)))
  try database.editDocument(id: originals[0].id, edit: .star, at: Date())
  try database.commit(.init(retention: .recent200))
  #expect(try database.eligibleRetentionCount() == 200)
  #expect(try database.documentHeader(id: originals[0].id) != nil)
  #expect(try database.documentHeader(id: originals[1].id) == nil)
  try database.editDocument(
    id: originals[0].id, edit: .moveToTrash, at: Date(timeIntervalSince1970: 10))
  try database.enqueueTrashCleanup(at: Date(timeIntervalSince1970: 20))
  try database.editDocument(
    id: originals[449].id, edit: .moveToTrash, at: Date(timeIntervalSince1970: 30))
  #expect(try database.documentHeader(id: originals[0].id) == nil)
  let reopened = try VaultDatabase(directory: directory)
  try drainCleanup(reopened)
  #expect(try reopened.documentHeader(id: originals[449].id)?.metadata.trashedAt != nil)
  #expect(try reopened.identifiers().count == 200)
}

private func cleanupRecord(_ sequence: Int) -> SessionRecord {
  SessionRecord(
    kind: .listen,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "capture")),
    metadata: .init(createdAt: Date(timeIntervalSince1970: Double(sequence))))
}

private func drainCleanup(_ database: VaultDatabase) throws {
  for _ in 0..<50 {
    guard try database.cleanupProgress().isPending else { return }
    try database.performCleanupSlice()
  }
  Issue.record("Bounded fixture cleanup did not finish")
}

private func cleanCleanupFixture(_ directory: URL) {
  do { try FileManager.default.removeItem(at: directory) } catch {
    Issue.record("Fixture cleanup failed: \(error)")
  }
}

@Test func explicitInsertionReplacesAPendingIdentityWithoutRevivingStaleUpdates() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { cleanCleanupFixture(directory) }
  let database = try VaultDatabase(directory: directory)
  let originals = (0..<250).map(cleanupRecord)
  try database.commit(.init(records: originals.map(VaultRecordWrite.insert)))
  var retained = originals[0]
  retained.transcript = "Explicitly saved again after clearing the archive."
  try database.commit(.init(records: [.insert(retained)], deletion: .all))
  #expect(try database.page(.init()).records.map(\.id) == [retained.id])
  #expect(try database.record(id: retained.id)?.transcript == retained.transcript)
  #expect(try database.workspacePage(.init(text: "Explicitly")).records.map(\.id) == [retained.id])

  let stale = try #require(originals.last)
  try database.commit(.init(records: [.update(stale)]))
  #expect(try database.record(id: stale.id) == nil)
  let reopened = try VaultDatabase(directory: directory)
  try drainCleanup(reopened)
  #expect(try reopened.page(.init()).records.map(\.id) == [retained.id])
  #expect(
    try reopened.sectionPage(.init(recordID: retained.id, section: .transcript))
      .blocks.map(\.text).joined() == retained.transcript)
}

@Test func explicitInsertionRebuildsAnIdenticalSourceAfterPartialReclamation() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { cleanCleanupFixture(directory) }
  let database = try VaultDatabase(directory: directory)
  var record = cleanupRecord(1)
  record.transcript = String(
    repeating: "An original passage that must survive reinsertion. ", count: 30_000)
  try database.commit(.init(records: [.insert(record)]))
  try database.commit(.init(deletion: .records([record.id])))
  #expect(try database.cleanupProgress().isPending)
  #expect(try database.record(id: record.id) == nil)

  try database.commit(.init(records: [.insert(record)]))
  let reopened = try VaultDatabase(directory: directory)
  try drainCleanup(reopened)
  #expect(try reopened.page(.init()).records.map(\.id) == [record.id])
  #expect(
    try reopened.sectionText(.init(recordID: record.id, section: .transcript)) == record.transcript)
  #expect(
    try reopened.sectionText(.init(recordID: record.id, section: .originalTranscript))
      == record.transcript)
}
