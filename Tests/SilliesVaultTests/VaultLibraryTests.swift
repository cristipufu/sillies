import Foundation
import SilliesCore
import SilliesPersistence
import Testing

@testable import SilliesVault

private func capture(_ index: Int) -> SessionRecord {
  SessionRecord(
    kind: .record,
    origin: .init(
      characterID: "mochi", characterName: "Mochi", source: .init(appName: "Meeting \(index)")),
    content: .init(
      text: .init(transcript: String(repeating: "long meeting ", count: 300) + " Ștefan \(index)")))
}
private func removeFixture(_ directory: URL) {
  do { try FileManager.default.removeItem(at: directory) } catch {
    Issue.record("Fixture cleanup: \(error)")
  }
}

@Test func largeVaultPagesDoNotLoadBodiesAndReopenKeepsSearchIndex() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeFixture(directory) }
  let library = VaultLibrary(directory: directory, cacheBytes: 12_000)
  let records = (0..<1_000).map(capture)
  _ = try await library.commit(.init(records: records.map(VaultRecordWrite.insert)))
  let first = try await library.page(.init())
  #expect(first.records.count == 200)
  #expect(first.total == 1_000)
  #expect(try await library.metrics().loadedBodies == 0)
  #expect(await library.retainedBodyBytes == 0)
  var edited = records[0]
  edited.transcript = "replacement text"
  _ = try await library.commit(.init(records: [.update(edited)]))
  #expect(try await library.metrics().writtenBodies == 1_001)
  for record in records.prefix(20) { _ = try await library.record(id: record.id) }
  #expect(await library.retainedBodyBytes <= 12_000)
  let reopened = VaultLibrary(directory: directory)
  let matches = try await reopened.page(.init(search: .init(kind: .record, query: "stefan")))
  #expect(matches.total == 999)
  #expect(try await reopened.metrics().indexedDocuments == 0)
  #expect(try await reopened.metrics().loadedBodies == 0)
  #expect(try await reopened.page(.init(after: first.nextCursor)).records.count == 200)
  _ = try await library.commit(.init(deletion: .records([edited.id])))
  _ = try await library.commit(.init(records: [.update(edited)]))
  #expect(try await library.record(id: edited.id) == nil)
  #expect(try await library.page(.init(search: .init(kind: nil, query: "replacement"))).total == 0)
}

@Test func oversizedVaultBodiesAreReturnedWithoutGrowingTheCache() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeFixture(directory) }
  let library = VaultLibrary(directory: directory, cacheBytes: 1_024)
  let record = capture(0)
  _ = try await library.commit(.init(records: [.insert(record)]))
  #expect(try await library.record(id: record.id)?.transcript == record.transcript)
  #expect(await library.retainedBodyBytes == 0)
}
