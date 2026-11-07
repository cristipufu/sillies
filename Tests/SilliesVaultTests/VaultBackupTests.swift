import Foundation
import SilliesCore
import SilliesPersistence
import Testing

@testable import SilliesVault

@Test func vaultBackupPreservesDraftsTrashAndAttachmentsWithoutChangingTheSource() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let directory = root.appendingPathComponent("source")
  defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
  let library = VaultLibrary(directory: directory)
  _ = try await library.snapshot()
  var record = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "vault", characterName: "", source: .init(appName: "Fixture")))
  _ = try await library.createDocument(
    record: record, metadata: .init(kind: .note, title: "Preserve me", modifiedAt: Date()),
    notes: "Saved text")
  record.imageFilename = "saved.png"
  _ = try await library.commit(
    .init(
      records: [.update(record)],
      attachments: [.init(filename: "saved.png", data: Data([1, 2, 3]))]))
  let location = VaultBlockLocation(recordID: record.id, section: .notes)
  try await library.saveDraft(
    .init(
      location: location, revision: library.sectionRevision(location), range: 0..<1,
      text: "Recovered text"))
  _ = try await library.editDocument(id: record.id, edit: .moveToTrash, at: Date())
  let exported = try await library.backup(to: root)
  let exportedFiles = Set(try FileManager.default.contentsOfDirectory(atPath: exported.path))
  #expect(
    exportedFiles == [
      VaultDatabase.filename, "BACKUP.txt", "saved.png",
    ])
  let reopened = VaultLibrary(directory: exported)
  _ = try await reopened.snapshot()
  #expect(try await reopened.documentHeader(id: record.id)?.metadata.trashedAt != nil)
  #expect(try await reopened.draft(location)?.text == "Recovered text")
  #expect(try await reopened.sectionPage(location).blocks.map(\.text).joined() == "Saved text")
  #expect(try await library.documentHeader(id: record.id)?.title == "Preserve me")
  #expect(try Data(contentsOf: exported.appendingPathComponent("saved.png")) == Data([1, 2, 3]))
}

@Test func vaultCancelledBackupNeverPublishesAnIncompleteFolder() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
  let library = VaultLibrary(directory: root.appendingPathComponent("source"))
  _ = try await library.snapshot()
  let task = Task { try await library.backup(to: root) }
  task.cancel()
  await #expect(throws: CancellationError.self) { try await task.value }
  #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["source"])
}

@Test func vaultBackupWithAMissingAttachmentNeverPublishesSuccess() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let directory = root.appendingPathComponent("source")
  defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
  let library = VaultLibrary(directory: directory)
  var record = SessionRecord(
    kind: .snap,
    origin: .init(characterID: "vault", characterName: "", source: .init(appName: "Fixture")))
  record.imageFilename = "removed.png"
  _ = try await library.commit(
    .init(
      records: [.insert(record)],
      attachments: [.init(filename: "removed.png", data: Data([1, 2, 3]))]))
  try FileManager.default.removeItem(at: directory.appendingPathComponent("removed.png"))
  await #expect(throws: (any Error).self) { try await library.backup(to: root) }
  #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["source"])
  #expect(try await library.documentHeader(id: record.id) != nil)
}
