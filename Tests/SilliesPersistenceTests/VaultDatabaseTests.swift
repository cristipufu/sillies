import Foundation
import SilliesCore
import SilliesPersistence
import Testing

@Test func recordRepositoryStoresVersionedRecordsIndividually() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeRepositoryFixture(directory) }
  let repository = try VaultDatabase(directory: directory)
  #expect(try repository.page(.init()).records.isEmpty)
  let record = SessionRecord(
    kind: .focus,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Test")))
  try repository.commit(.init(records: [.insert(record)]))
  #expect(try repository.page(.init()).records.map(\.id) == [record.id])
  let data = try Data(contentsOf: directory.appendingPathComponent(VaultDatabase.filename))
  #expect(data.starts(with: Data("SQLite format 3".utf8)))
}

@Test func recordRepositoryDistinguishesCorruptionFromMissingStorage() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeRepositoryFixture(directory) }
  let files = VaultFileStorage(directory: directory)
  let corrupted = Data("{ incomplete saved sessions".utf8)
  try files.write(corrupted, named: VaultDatabase.filename)
  #expect(throws: (any Error).self) {
    try VaultDatabase(directory: directory)
  }
  #expect(try Data(contentsOf: files.url(for: VaultDatabase.filename)) == corrupted)
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

@Test func vaultCursorSurvivesInsertionDeletionAndSubsecondTies() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeRepositoryFixture(directory) }
  let database = try VaultDatabase(directory: directory)
  func record(_ time: Double) -> SessionRecord {
    .init(
      kind: .record,
      origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Test")),
      metadata: .init(createdAt: Date(timeIntervalSince1970: time)))
  }
  let records = [record(10.9), record(10.5), record(10.5), record(10.1), record(9.9)]
  try database.commit(.init(records: records.map { .insert($0) }))
  let first = try database.page(.init(limit: 2))
  let cursor = try #require(first.nextCursor)
  let new = record(11)
  try database.commit(.init(records: [.insert(new)], deletion: .records([first.records[0].id])))
  let remaining = try database.page(.init(after: cursor, limit: 3))
  #expect(remaining.records.count == 3)
  #expect(Set(first.records.map(\.id) + remaining.records.map(\.id)) == Set(records.map(\.id)))
  #expect(remaining.records.allSatisfy { VaultPageCursor($0) < cursor })
}
