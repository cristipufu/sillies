import Foundation
import SilliesCore
import SilliesPersistence
import Testing

@Test func recordRepositoryPreservesTheExistingDiskFormat() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeRepositoryFixture(directory) }
  let repository = SessionRecordRepository(directory: directory)
  #expect(try repository.load().isEmpty)
  let record = SessionRecord(
    kind: .focus,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Test")))
  try repository.save([record])
  #expect(try repository.load().map(\.id) == [record.id])
  let data = try Data(contentsOf: directory.appendingPathComponent("sessions.json"))
  #expect(try JSONSerialization.jsonObject(with: data) is [[String: Any]])
}

@Test func recordRepositoryDistinguishesCorruptionFromMissingStorage() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeRepositoryFixture(directory) }
  let files = VaultFileStorage(directory: directory)
  let corrupted = Data("{ incomplete saved sessions".utf8)
  try files.write(corrupted, named: "sessions.json")
  #expect(throws: (any Error).self) {
    try SessionRecordRepository(directory: directory).load()
  }
  #expect(try Data(contentsOf: files.url(for: "sessions.json")) == corrupted)
}

private func removeRepositoryFixture(_ directory: URL) {
  do {
    try FileManager.default.removeItem(at: directory)
  } catch CocoaError.fileNoSuchFile {
    return
  } catch {
    Issue.record("Could not remove repository fixture: \(error)")
  }
}
