import Foundation
import SilliesCore
import SilliesPersistence
import Testing

@Test func unsafeAttachmentNamesCannotChangeVaultOrParentContents() throws {
  let fixture = try VaultStorageFixture()
  defer { fixture.remove() }
  let files = VaultFileStorage(directory: fixture.vault)
  for filename in ["", ".", "..", "/", "/tmp/..", "../outside.txt", "nested/file", "bad\0name"] {
    #expect(throws: (any Error).self) { try files.removeAttachment(named: filename) }
    #expect(throws: (any Error).self) { try files.write(Data(), named: filename) }
  }
  for filename in ["sessions.json", "SESSIONS.JSON", "vault.sqlite", "VAULT.SQLITE-WAL", "folder"] {
    #expect(throws: (any Error).self) { try files.removeAttachment(named: filename) }
  }
  try fixture.expectSentinelsPreserved()
  try files.write(Data("audio".utf8), named: "recording.m4a")
  try files.removeAttachment(named: "recording.m4a")
  try files.removeAttachment(named: "recording.m4a")
  #expect(
    !FileManager.default.fileExists(
      atPath: fixture.vault.appendingPathComponent("recording.m4a").path))
}

@Test func attachmentRemovalUnlinksSymlinksWithoutRemovingTheirTarget() throws {
  let fixture = try VaultStorageFixture()
  defer { fixture.remove() }
  let link = fixture.vault.appendingPathComponent("link")
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.root)
  try VaultFileStorage(directory: fixture.vault).removeAttachment(named: "link")
  try fixture.expectSentinelsPreserved()
}

@Test func repositoryRejectsUnsafeDecodedAttachmentsWithoutReplacingMetadata() throws {
  let fixture = try VaultStorageFixture()
  defer { fixture.remove() }
  var record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Test")))
  record.audioFilename = "/"
  let repository = try VaultDatabase(directory: fixture.vault)
  #expect(throws: (any Error).self) { try repository.commit(.init(records: [.insert(record)])) }
  #expect(try repository.page(.init()).total == 0)
  try fixture.expectSentinelsPreserved()
}

private struct VaultStorageFixture {
  let root: URL
  var vault: URL { root.appendingPathComponent("Vault", isDirectory: true) }
  private let sentinel = Data("keep".utf8)
  private var paths: [URL] {
    [
      root.appendingPathComponent("outside.txt"), vault.appendingPathComponent("sessions.json"),
      vault.appendingPathComponent("folder/inside.txt"),
    ]
  }

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: vault.appendingPathComponent("folder"), withIntermediateDirectories: true)
    for path in paths { try sentinel.write(to: path) }
  }

  func expectSentinelsPreserved() throws {
    for path in paths { #expect(try Data(contentsOf: path) == sentinel) }
  }

  func remove() {
    do { try FileManager.default.removeItem(at: root) } catch {
      Issue.record("Could not remove storage fixture: \(error)")
    }
  }
}
