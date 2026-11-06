import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test(arguments: [1_000, 10_000])
func semanticMemorySearchKeepsBodiesAndResultsBoundedAtScale(_ count: Int) async throws {
  let fixture = try SearchEmbeddingFixture()
  defer { fixture.remove() }
  let dimensions = 384
  let ordinary = try SearchEmbedding(
    space: "scale", values: [0, 1] + Array(repeating: 0, count: dimensions - 2))
  let target = try SearchEmbedding(
    space: "scale", values: [1, 0] + Array(repeating: 0, count: dimensions - 2))
  for index in 0..<count {
    let receipt = try fixture.save(key: "fact_\(index)", value: "Synthetic fact \(index)")
    try fixture.database.saveSearchEmbedding(
      index == count / 2 ? target : ordinary,
      for: .init(owner: fixture.handle.companionID, memory: receipt.saved), provider: "scale")
  }
  let reader = try ConversationSearchDatabase(directory: fixture.directory)
  let started = ContinuousClock.now
  let result = try reader.semanticMemories(
    .init(handle: fixture.handle, text: "target"), embedding: target, provider: "scale")
  #expect(result.count == 4)
  #expect(result.first?.key == "fact_\(count / 2)")
  print(
    "SEMANTIC SCALE facts=\(count) dimensions=\(dimensions) query=\(started.duration(to: .now))")
}

@Test func memoryVectorsSurviveRestartAndRefuseStaleCorrections() async throws {
  let fixture = try SearchEmbeddingFixture()
  defer { fixture.remove() }
  let saved = try fixture.save(key: "commute", value: "I cycle to work")
  let item = MemoryIndexItem(owner: fixture.handle.companionID, memory: saved.saved)
  let vector = try SearchEmbedding(space: "space-v1", values: [1, 0])
  #expect(try fixture.database.saveSearchEmbedding(vector, for: item, provider: "test"))
  let reopened = try ConversationDatabase(directory: fixture.directory)
  #expect(try reopened.pendingSearchEmbeddings(provider: "test").isEmpty)
  let reader = try ConversationSearchDatabase(directory: fixture.directory)
  let query = CompanionMemoryQuery(handle: fixture.handle, text: "How do I travel?")
  #expect(
    try reader.semanticMemories(query, embedding: vector, provider: "test").map(\.id) == [
      saved.saved.id
    ])
  let correction = MemoryWrite(
    handle: fixture.handle,
    fact: .init(key: "commute", value: "I take the bus"), source: fixture.source, savedAt: Date()
  )
  .replacing(saved.saved.reference)
  let changed = try reopened.remember(correction)
  #expect(try reader.semanticMemories(query, embedding: vector, provider: "test").isEmpty)
  #expect(try !reopened.saveSearchEmbedding(vector, for: item, provider: "test"))
  #expect(
    try reopened.pendingSearchEmbeddings(provider: "test").first?.memory.revision
      == changed.saved.revision)
  let current = MemoryIndexItem(owner: fixture.handle.companionID, memory: changed.saved)
  #expect(try reopened.saveSearchEmbedding(vector, for: current, provider: "test"))
  let undone = try reopened.undoMemory(fixture.handle, receiptID: changed.id)
  #expect(try !reopened.saveSearchEmbedding(vector, for: current, provider: "test"))
  #expect(
    try reader.semanticMemories(
      .init(handle: undone.handle, text: "travel"), embedding: vector, provider: "test"
    ).isEmpty)
  #expect(
    try reopened.pendingSearchEmbeddings(provider: "test").first?.memory.value == "I cycle to work")
}

@Test func memoryRankingMigrationPreservesVectorsAndTheirInvalidation() async throws {
  let fixture = try SearchEmbeddingFixture()
  defer { fixture.remove() }
  let saved = try fixture.save(key: "drink", value: "tea")
  let vector = try SearchEmbedding(space: "migration", values: [1, 0, 0])
  try fixture.database.saveSearchEmbedding(
    vector, for: .init(owner: fixture.handle.companionID, memory: saved.saved), provider: "test")
  try fixture.restoreVersionThree()
  let reopened = try ConversationDatabase(directory: fixture.directory)
  let reader = try ConversationSearchDatabase(directory: fixture.directory)
  let query = CompanionMemoryQuery(handle: fixture.handle, text: "beverage")
  #expect(try reopened.sql.integer("PRAGMA user_version") == ConversationDatabase.schemaVersion)
  #expect(try reader.semanticMemories(query, embedding: vector, provider: "test") == [saved.saved])
  #expect(try reopened.pendingSearchEmbeddings(provider: "test").isEmpty)
  let forgotten = try reopened.forget(fixture.handle, id: saved.saved.id)
  #expect(
    try reader.semanticMemories(
      .init(handle: forgotten.handle, text: "beverage"), embedding: vector, provider: "test"
    ).isEmpty)
}

@Test func memoryRankingMigrationRejectsOrphansWithoutDiscardingThePriorIndex() async throws {
  let fixture = try SearchEmbeddingFixture()
  defer { fixture.remove() }
  let saved = try fixture.save(key: "drink", value: "tea")
  let vector = try SearchEmbedding(space: "migration", values: [1, 0])
  try fixture.database.saveSearchEmbedding(
    vector, for: .init(owner: fixture.handle.companionID, memory: saved.saved), provider: "test")
  try fixture.restoreVersionThree()
  try fixture.database.sql.execute(
    "INSERT INTO memory_embeddings(provider,id,space,vector) VALUES('test','missing','migration',?)",
    [.data(SearchVectorStorage.encode(vector.values))])
  #expect(throws: ConversationStorageError.self) {
    _ = try ConversationDatabase(directory: fixture.directory)
  }
  #expect(try fixture.database.sql.integer("PRAGMA user_version") == 3)
  #expect(try fixture.database.sql.integer("SELECT COUNT(*) FROM memory_embeddings") == 2)
  #expect(try fixture.database.sql.integer("SELECT COUNT(*) FROM companion_memories") == 1)
}

@Test func equallySimilarMemoriesKeepStableIdentityOrderingAcrossRestarts() async throws {
  let fixture = try SearchEmbeddingFixture()
  defer { fixture.remove() }
  let vector = try SearchEmbedding(space: "ties", values: [1, 0])
  var expected: [String] = []
  for index in 0..<9 {
    let saved = try fixture.save(key: "fact_\(index)", value: "Synthetic fact \(index)").saved
    expected.append(saved.id.uuidString)
    try fixture.database.saveSearchEmbedding(
      vector, for: .init(owner: fixture.handle.companionID, memory: saved), provider: "test")
  }
  expected.sort()
  for _ in 0..<2 {
    let reader = try ConversationSearchDatabase(directory: fixture.directory)
    let matches = try reader.semanticMemories(
      .init(handle: fixture.handle, text: "fact"), embedding: vector, provider: "test")
    #expect(matches.map { $0.id.uuidString } == Array(expected.prefix(4)))
  }
}

@Test func strongerVectorsOutsideTheQueryScopeCannotDisplaceItsMemories() async throws {
  let fixture = try SearchEmbeddingFixture()
  defer { fixture.remove() }
  let ours = try fixture.save(key: "ours", value: "Our fact").saved
  try fixture.database.saveSearchEmbedding(
    .init(space: "current", values: [0, 1]),
    for: .init(owner: fixture.handle.companionID, memory: ours), provider: "test")
  let foreign = try fixture.database.open(.init(id: "bolt", name: "Bolt")).handle
  let source = ChatMessage(role: .user, text: "Synthetic foreign fact.")
  try fixture.database.save(
    .init(handle: foreign, messages: [source], checkpoint: .init(), savedAt: Date()))
  for index in 0..<6 {
    let saved = try fixture.database.remember(
      .init(
        handle: foreign, fact: .init(key: "foreign_\(index)", value: source.text),
        source: .init(messageID: source.id, quote: source.text), savedAt: Date())
    ).saved
    try fixture.database.saveSearchEmbedding(
      .init(space: "current", values: [1, 0]),
      for: .init(owner: foreign.companionID, memory: saved), provider: "test")
  }
  for (provider, space) in [("other-provider", "current"), ("test", "other-space")] {
    let saved = try fixture.save(key: provider + space, value: "Other model's fact").saved
    try fixture.database.saveSearchEmbedding(
      .init(space: space, values: [1, 0]),
      for: .init(owner: fixture.handle.companionID, memory: saved), provider: provider)
  }
  let reader = try ConversationSearchDatabase(directory: fixture.directory)
  let result = try reader.semanticMemories(
    .init(handle: fixture.handle, text: "fact"),
    embedding: .init(space: "current", values: [1, 0]), provider: "test")
  #expect(result == [ours])
}

@Test func forgettingAndClearingCannotResurrectInFlightEmbeddings() async throws {
  let fixture = try SearchEmbeddingFixture()
  defer { fixture.remove() }
  let saved = try fixture.save(key: "instrument", value: "violin")
  let item = MemoryIndexItem(owner: fixture.handle.companionID, memory: saved.saved)
  _ = try fixture.database.forget(fixture.handle, id: saved.saved.id)
  #expect(try !fixture.database.saveSearchEmbedding(nil, for: item, provider: "test"))
  let current = try fixture.database.open(.init(id: "pogo", name: "Pogo"))
  _ = try fixture.database.clear(current.handle)
  #expect(try !fixture.database.saveSearchEmbedding(nil, for: item, provider: "test"))
  #expect(try fixture.database.memoryIndexProgress(provider: "test").processed == 0)
}

@Test func semanticSearchIsOwnerAndVectorSpaceScopedAndUnsupportedFactsDoNotLoop() async throws {
  let fixture = try SearchEmbeddingFixture()
  defer { fixture.remove() }
  let first = try fixture.save(key: "drink", value: "tea")
  let item = MemoryIndexItem(owner: fixture.handle.companionID, memory: first.saved)
  #expect(try fixture.database.saveSearchEmbedding(nil, for: item, provider: "apple"))
  #expect(try fixture.database.pendingSearchEmbeddings(provider: "apple").isEmpty)
  #expect(try fixture.database.memoryIndexProgress(provider: "apple").searchable == 0)
  let vector = try SearchEmbedding(space: "old", values: [1, 0])
  try fixture.database.saveSearchEmbedding(vector, for: item, provider: "e5")
  let reader = try ConversationSearchDatabase(directory: fixture.directory)
  let query = CompanionMemoryQuery(handle: fixture.handle, text: "beverage")
  #expect(
    try reader.semanticMemories(
      query, embedding: .init(space: "new", values: [1, 0]), provider: "e5"
    ).isEmpty)
  let other = try fixture.database.open(.init(id: "bolt", name: "Bolt"))
  #expect(
    try reader.semanticMemories(
      .init(handle: other.handle, text: "beverage"), embedding: vector, provider: "e5"
    ).isEmpty)
  try fixture.database.resetSearchEmbeddings(provider: "apple")
  #expect(try fixture.database.pendingSearchEmbeddings(provider: "apple").count == 1)
  try fixture.database.removeSearchEmbeddings(except: "apple")
  #expect(try fixture.database.memoryIndexProgress(provider: "e5").processed == 0)
}

private struct SearchEmbeddingFixture {
  let directory: URL
  let database: ConversationDatabase
  let handle: ConversationHandle
  let source: MemorySource
  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    database = try ConversationDatabase(directory: directory)
    handle = try database.open(.init(id: "pogo", name: "Pogo")).handle
    let message = ChatMessage(role: .user, text: "Synthetic memory source.")
    source = .init(messageID: message.id, quote: message.text)
    try database.save(
      .init(handle: handle, messages: [message], checkpoint: .init(), savedAt: Date()))
  }
  func save(key: String, value: String) throws -> MemoryReceipt {
    try database.remember(
      .init(handle: handle, fact: .init(key: key, value: value), source: source, savedAt: Date()))
  }
  func restoreVersionThree() throws {
    try database.sql.execute("DROP TABLE personal_facts")
    try database.sql.execute("DROP TABLE personal_fact_state")
    try database.sql.execute("DROP INDEX conversation_messages_date")
    try database.sql.execute("DROP INDEX memory_embeddings_scope")
    try database.sql.execute("ALTER TABLE memory_embeddings DROP COLUMN owner")
    try database.sql.execute("PRAGMA user_version=3")
  }
  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
}
