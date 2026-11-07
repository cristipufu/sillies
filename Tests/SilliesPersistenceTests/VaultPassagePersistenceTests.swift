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
  var transcriptPassage: VaultPassage?
  while let passage = try fixture.database.pendingPassage() {
    try fixture.database.savePassage(passage)
    if passage.text.contains("bicycle") { transcriptPassage = passage }
  }
  let passage = try #require(transcriptPassage)
  var transcriptItem: VaultEmbeddingItem?
  while let pending = try fixture.database.pendingVaultEmbedding(provider: "test") {
    if pending.text.contains("bicycle") {
      transcriptItem = pending
      break
    }
    try fixture.database.saveVaultEmbedding(nil, for: pending, provider: "test")
  }
  let item = try #require(transcriptItem)
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
  // Recreate the schema that actually existed in version 1, not a newer schema with a changed label.
  var workspaceTriggers: [String] = []
  try fixture.database.sql.rows("SELECT name FROM sqlite_master WHERE type='trigger'") { row in
    workspaceTriggers.append(try VaultSQLConnection.text(row))
  }
  for name in workspaceTriggers { try fixture.database.sql.execute("DROP TRIGGER \(name)") }
  try fixture.database.sql.execute("DROP VIEW searchable_blocks")
  try fixture.database.sql.execute("DROP VIEW available_records")
  for name in [
    "content_search", "content_blocks", "content_sections", "content_backfill", "vault_drafts",
    "workspace", "document_identities", "vault_collections", "vault_collection_items", "vault_tags",
    "vault_saved_searches", "library_counts", "trash_counts", "embedding_cursors",
    "embedding_counts", "embedding_spaces", "semantic_counts", "vector_changes",
    "content_substrings", "search_index_content", "vault_metadata_drafts", "source_facets",
    "recording_bookmarks", "file_references", "pending_deletions", "vault_cleanup",
    "cleanup_policy",
  ] {
    try fixture.database.sql.execute("DROP TABLE \(name)")
  }
  for name in ["passage_vectors", "passages", "passage_sources"] {
    try fixture.database.sql.execute("DROP TABLE \(name)")
  }
  for name in [
    "records_source_app", "records_source_companion", "records_source_language",
    "records_retention", "records_modified", "records_visibility",
  ] {
    try fixture.database.sql.execute("DROP INDEX \(name)")
  }
  try fixture.database.sql.execute("ALTER TABLE records DROP COLUMN modified")
  try fixture.database.sql.execute(
    "INSERT INTO documents(id,body) VALUES(?,?)",
    [.text(record.id.uuidString), .text(record.transcript)])
  try fixture.database.sql.execute("PRAGMA user_version=1")
  let migrated = try VaultDatabase(directory: fixture.directory)
  #expect(try migrated.search(.init(query: "preserved")).map(\.header.id) == [record.id])
  #expect(migrated.metrics.loadedBodies == 0)
  try migrated.prepareContent(id: record.id)
  #expect(try migrated.pendingPassage()?.recordID == record.id)
}

@Test func vaultPassageRejectsOverflowAndOutOfBoundsOffsets() throws {
  let fixture = try VaultPassageFixture()
  defer { fixture.remove() }
  for offset in [-1, Int.max] {
    #expect(throws: CocoaError.self) {
      try fixture.database.savePassage(
        .init(
          recordID: UUID(), revision: "test", offset: offset,
          text: "text", isLast: true, blockID: 1))
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
