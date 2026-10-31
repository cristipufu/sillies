import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

private func attachmentRecord() -> SessionRecord {
  var record = SessionRecord(
    kind: .snap,
    origin: .init(
      characterID: "mochi", characterName: "Mochi", source: .init(appName: "Fixture")))
  record.imageFilename = "saved.png"
  return record
}

@Test func failedVaultIndexCommitPreservesReferencedAttachmentsAndCanRetry() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { cleanCommitFixture(directory) }
  let files = VaultFileStorage(directory: directory)
  let record = attachmentRecord()
  let repository = VaultCommitRepository(directory: directory)
  try repository.commit(
    [record], attachments: [.init(filename: "saved.png", data: Data([1, 2]))], removing: [])
  let original = try Data(contentsOf: files.url(for: "sessions.json"))
  let failing = VaultCommitRepository(directory: directory) { _ in
    throw CocoaError(.fileWriteOutOfSpace)
  }
  #expect(throws: (any Error).self) {
    try failing.commit([], attachments: [], removing: ["saved.png"])
  }
  #expect(try Data(contentsOf: files.url(for: "sessions.json")) == original)
  #expect(try Data(contentsOf: files.attachmentURL(for: "saved.png")) == Data([1, 2]))
  // Reopening after the interrupted commit protects everything still referenced by the old index.
  #expect(try repository.load().map(\.id) == [record.id])
  #expect(FileManager.default.fileExists(atPath: try files.attachmentURL(for: "saved.png").path))
  try repository.commit([], attachments: [], removing: ["saved.png"])
  #expect(!FileManager.default.fileExists(atPath: try files.attachmentURL(for: "saved.png").path))
}

@Test func vaultStartupFinishesOnlyJournaledUnreferencedAttachmentCleanup() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { cleanCommitFixture(directory) }
  let files = VaultFileStorage(directory: directory)
  let record = attachmentRecord()
  try SessionRecordRepository(directory: directory).save([record])
  for name in ["saved.png", "retired.m4a", "unrelated.txt"] {
    try files.write(Data([1]), named: name)
  }
  try files.write(
    JSONEncoder().encode(["saved.png", "retired.m4a"]), named: VaultCommitRepository.journalFilename
  )
  _ = try VaultCommitRepository(directory: directory).load()
  #expect(FileManager.default.fileExists(atPath: try files.url(for: "saved.png").path))
  #expect(FileManager.default.fileExists(atPath: try files.url(for: "unrelated.txt").path))
  #expect(!FileManager.default.fileExists(atPath: try files.url(for: "retired.m4a").path))
  #expect(throws: (any Error).self) {
    try files.attachmentURL(for: VaultCommitRepository.journalFilename)
  }
}

private func cleanCommitFixture(_ directory: URL) {
  do { try FileManager.default.removeItem(at: directory) } catch {
    Issue.record("Fixture cleanup failed: \(error)")
  }
}
