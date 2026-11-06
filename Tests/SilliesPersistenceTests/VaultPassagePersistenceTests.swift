import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func vaultPassagesReachLateUnicodeEvidenceWithoutLoadingRecordBodies() throws {
  let fixture = try VaultPassageFixture()
  defer { fixture.remove() }
  let record = fixture.record(
    String(repeating: "🌳 e\u{301} ", count: 900) + "the launch was postponed")
  try fixture.database.commit(.init(records: [.insert(record)]))
  var passages: [VaultPassage] = []
  while let passage = try fixture.database.pendingPassage() {
    #expect(passage.text.unicodeScalars.count <= VaultPassage.maximumScalars)
    #expect(try fixture.database.savePassage(passage))
    #expect(try !fixture.database.savePassage(passage))
    passages.append(passage)
  }
  #expect(passages.count > 3)
  #expect(passages.last?.text.contains("launch was postponed") == true)
  #expect(fixture.database.metrics.loadedBodies == 0)
  let reopened = try VaultDatabase(directory: fixture.directory)
  #expect(try reopened.pendingPassage() == nil)
  #expect(try reopened.vaultIndexProgress(provider: "test").total == passages.count)
}

@Test func vaultVectorsRejectEditsDeletionsAndProviderSpaceMismatches() throws {
  let fixture = try VaultPassageFixture()
  defer { fixture.remove() }
  var record = fixture.record("We travel by bicycle.")
  try fixture.database.commit(.init(records: [.insert(record)]))
  let passage = try #require(try fixture.database.pendingPassage())
  try fixture.database.savePassage(passage)
  let item = try #require(try fixture.database.pendingVaultEmbedding(provider: "test"))
  let vector = try SearchEmbedding(space: "one", values: [1, 0])
  #expect(try fixture.database.saveVaultEmbedding(vector, for: item, provider: "test"))
  let reader = try VaultSemanticSearchDatabase(directory: fixture.directory)
  let query = VaultSearchRequest(query: "commute")
  #expect(
    try reader.search(query, embedding: vector, provider: "test").map(\.header.id) == [record.id])
  #expect(try reader.search(query, embedding: vector, provider: "other").isEmpty)
  #expect(
    try reader.search(query, embedding: .init(space: "two", values: [1, 0]), provider: "test")
      .isEmpty)
  record.transcript = "We take the train."
  try fixture.database.commit(.init(records: [.update(record)]))
  #expect(try !fixture.database.saveVaultEmbedding(vector, for: item, provider: "test"))
  #expect(try !fixture.database.savePassage(passage))
  #expect(try reader.search(query, embedding: vector, provider: "test").isEmpty)
  let replacement = try #require(try fixture.database.pendingPassage())
  try fixture.database.savePassage(replacement)
  let pending = try #require(try fixture.database.pendingVaultEmbedding(provider: "test"))
  try fixture.database.commit(.init(deletion: .records([record.id])))
  #expect(try !fixture.database.saveVaultEmbedding(vector, for: pending, provider: "test"))
  #expect(try fixture.database.vaultIndexProgress(provider: "test").total == 0)
  #expect(try fixture.database.sql.integer("SELECT COUNT(*) FROM passage_vectors") == 0)
}

@Test func vaultVersionOneMigrationBackfillsExistingDocuments() throws {
  let fixture = try VaultPassageFixture()
  defer { fixture.remove() }
  let record = fixture.record("A preserved meeting")
  try fixture.database.commit(.init(records: [.insert(record)]))
  for name in ["record_passage_delete", "passage_delete"] {
    try fixture.database.sql.execute("DROP TRIGGER \(name)")
  }
  for name in ["passage_vectors", "passages", "passage_sources"] {
    try fixture.database.sql.execute("DROP TABLE \(name)")
  }
  try fixture.database.sql.execute("PRAGMA user_version=1")
  let migrated = try VaultDatabase(directory: fixture.directory)
  #expect(try migrated.pendingPassage()?.recordID == record.id)
  #expect(try migrated.search(.init(query: "preserved")).map(\.header.id) == [record.id])
  #expect(migrated.metrics.loadedBodies == 0)
}

@Test func vaultPassageRejectsOverflowAndOutOfBoundsOffsets() throws {
  let fixture = try VaultPassageFixture()
  defer { fixture.remove() }
  for offset in [-1, Int.max] {
    #expect(throws: CocoaError.self) {
      try fixture.database.savePassage(
        .init(
          recordID: UUID(), revision: "test", offset: offset,
          text: "text", isLast: true))
    }
  }
}

private struct VaultPassageFixture {
  let directory: URL
  let database: VaultDatabase
  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    database = try VaultDatabase(directory: directory)
  }
  func record(_ text: String) -> SessionRecord {
    .init(
      kind: .record,
      origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
      content: .init(text: .init(transcript: text)))
  }
  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
}
