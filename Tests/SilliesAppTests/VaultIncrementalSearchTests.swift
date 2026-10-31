import Foundation
import SilliesCore
import Testing

@testable import SilliesApp

@Test func largeVaultSearchReindexesOnlyChangedDocumentsAndRejectsStaleDeletedText() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let service = VaultSearchService(directory: directory)
  var records = (0..<1_000).map { index in
    SessionRecord(
      kind: .record,
      origin: .init(
        characterID: "mochi", characterName: "Mochi", source: .init(appName: "Fixture")),
      content: .init(
        text: .init(
          transcript: String(repeating: "meeting notes ", count: 100) + " Ștefan \(index)")))
  }
  var versions = Dictionary(uniqueKeysWithValues: records.map { ($0.id, 1) })
  let original = VaultSearchService.Snapshot(records: records, versions: versions, revision: 1)
  #expect(
    try await service.search(.init(kind: nil, query: "stefan"), snapshot: original).count == 1_000)
  #expect(await service.indexedDocumentCount == 1_000)
  records[0].transcript = "replacement text"
  versions[records[0].id] = 2
  let edited = VaultSearchService.Snapshot(records: records, versions: versions, revision: 2)
  #expect(
    try await service.search(.init(kind: nil, query: "replacement"), snapshot: edited) == [
      records[0].id
    ])
  #expect(await service.indexedDocumentCount == 1_001)
  try await service.remove([records[0].id], at: 3)
  #expect(
    try await service.search(.init(kind: nil, query: "replacement"), snapshot: edited).isEmpty)
  #expect(await service.indexedDocumentCount == 1_001)
}
