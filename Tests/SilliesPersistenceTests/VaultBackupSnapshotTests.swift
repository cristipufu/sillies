import Foundation
import SilliesCore
import SilliesPersistence
import Testing

@Test func vaultBackupKeepsOneSnapshotWhileTheSourceContinuesSaving() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let sourceDirectory = root.appendingPathComponent("source")
  let destinationDirectory = root.appendingPathComponent("backup")
  defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
  let source = try VaultDatabase(directory: sourceDirectory)
  try FileManager.default.createDirectory(
    at: destinationDirectory, withIntermediateDirectories: true)
  let record = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "vault", characterName: "", source: .init(appName: "Fixture")))
  _ = try source.createDocument(
    record: record, metadata: .init(kind: .note, title: "Before backup", modifiedAt: Date()),
    notes: String(repeating: "A saved paragraph. ", count: 120_000))
  let backup = try VaultSQLiteBackup(
    source: sourceDirectory.appendingPathComponent(VaultDatabase.filename),
    destination: destinationDirectory.appendingPathComponent(VaultDatabase.filename))
  #expect(try !backup.step(), "The fixture must exercise more than one copy step.")
  try source.editDocument(id: record.id, edit: .rename("Saved during backup"), at: Date())
  while try !backup.step() {}
  let snapshot = try VaultDatabase(reading: destinationDirectory)
  #expect(try snapshot.documentHeader(id: record.id)?.title == "Before backup")
  #expect(try source.documentHeader(id: record.id)?.title == "Saved during backup")
  #expect(
    try snapshot.sectionPage(.init(recordID: record.id, section: .notes)).blocks.count
      == VaultSectionPage.maximumBlocks)
  #expect(
    try FileManager.default.contentsOfDirectory(atPath: destinationDirectory.path) == [
      VaultDatabase.filename
    ])
}
