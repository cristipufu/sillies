import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func vaultFileRelinkingUpdatesSearchAndNeverDeletesTheExternalFile() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
  let directory = root.appendingPathComponent("Vault")
  let database = try VaultDatabase(directory: directory)
  let external = root.appendingPathComponent("renamed-document.txt")
  try Data("Owned by the user, outside the Vault".utf8).write(to: external)
  var record = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")))
  record.stashedItems = [
    root.appendingPathComponent("missing-document.txt").path, "Ordinary text",
    "https://example.com",
  ]
  try database.commit(.init(records: [.insert(record)]))
  let reference = try #require(database.fileReferences(id: record.id).first)
  #expect(try database.fileReferences(id: record.id).count == 1)
  try database.relink(reference, to: external)
  let relinked = try #require(database.fileReferences(id: record.id).first)
  #expect(relinked.id == reference.id && relinked.path == external.path)
  #expect(
    try database.workspacePage(.init(text: "renamed-document")).records.map(\.id) == [record.id])
  // An unrelated capture update must not undo the user's relink.
  record.isProtected = true
  try database.commit(.init(records: [.update(record)]))
  #expect(try database.fileReferences(id: record.id).first == relinked)
  #expect(throws: VaultEditingError.self) { try database.relink(reference, to: external) }
  try database.commit(.init(deletion: .records([record.id])))
  #expect(try database.fileReferences(id: record.id).isEmpty)
  #expect(
    try String(contentsOf: external, encoding: .utf8) == "Owned by the user, outside the Vault")
}
