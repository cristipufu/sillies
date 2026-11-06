import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func personalFactsKeepSharedAndCompanionScopeAcrossRestart() async throws {
  let fixture = try PersonalFactsFixture()
  defer { fixture.remove() }
  let pogo = fixture.handle
  let bolt = try fixture.database.open(.init(id: "bolt", name: "Bolt")).handle
  let shared = try fixture.database.savePersonalFact(
    .init(handle: pogo, scope: .shared, fact: .init(key: "name", value: "Alex")))
  let specific = try fixture.database.savePersonalFact(
    .init(handle: pogo, scope: .companion, fact: .init(key: "name", value: "Al")))
  #expect(shared.revision != specific.revision)
  #expect(specific.contextFacts.map(\.fact.value) == ["Al"])
  let reopened = try ConversationDatabase(directory: fixture.directory)
  #expect(try reopened.personalFacts(bolt).contextFacts.map(\.fact.value) == ["Alex"])
  #expect(try reopened.personalFacts(pogo).facts.count == 2)
  #expect(try reopened.memoryPage(.init(handle: pogo)).facts.isEmpty)
}

@Test func personalFactEditsRejectStaleRevisionsAndRespectLimits() async throws {
  let fixture = try PersonalFactsFixture()
  defer { fixture.remove() }
  let original = try fixture.database.savePersonalFact(
    .init(handle: fixture.handle, scope: .companion, fact: .init(key: "name", value: "Alex")))
  let first = try #require(original.facts.first)
  let changed = try fixture.database.savePersonalFact(
    .init(
      handle: fixture.handle, scope: .companion, fact: .init(key: "name", value: "Al"),
      replacing: first))
  #expect(changed.facts.first?.id == first.id)
  #expect(throws: PersonalFactError.changed) {
    try fixture.database.removePersonalFact(first, handle: fixture.handle)
  }
  #expect(throws: PersonalFactError.duplicate) {
    try fixture.database.savePersonalFact(
      .init(handle: fixture.handle, scope: .companion, fact: .init(key: "Name", value: "Bob")))
  }
  for index in 1..<PersonalFact.maximumPerScope {
    _ = try fixture.database.savePersonalFact(
      .init(
        handle: fixture.handle, scope: .companion,
        fact: .init(key: "topic\(index)", value: "A preference")))
  }
  #expect(throws: PersonalFactError.limit) {
    try fixture.database.savePersonalFact(
      .init(handle: fixture.handle, scope: .companion, fact: .init(key: "extra", value: "Extra")))
  }
  #expect(
    try fixture.database.personalFacts(fixture.handle).facts.count == PersonalFact.maximumPerScope)
  _ = try fixture.database.removePersonalFact(
    try #require(changed.facts.first), handle: fixture.handle)
  #expect(
    try fixture.database.personalFacts(fixture.handle).facts.count == PersonalFact.maximumPerScope
      - 1)
}

@Test(arguments: ConversationDataRemoval.allCases)
func conversationDeletionSeparatesMessagesLearnedMemoriesAndPinnedFacts(
  _ removal: ConversationDataRemoval
) async throws {
  let fixture = try PersonalFactsFixture()
  defer { fixture.remove() }
  let message = ChatMessage(role: .user, text: "I enjoy painting.")
  try fixture.database.save(
    .init(handle: fixture.handle, messages: [message], checkpoint: .init(), savedAt: Date()))
  let receipt = try fixture.database.remember(
    .init(
      handle: fixture.handle, fact: .init(key: "hobby", value: "painting"),
      source: .init(messageID: message.id, quote: message.text), savedAt: Date()))
  _ = try fixture.database.savePersonalFact(
    .init(handle: fixture.handle, scope: .companion, fact: .init(key: "name", value: "Alex")))
  let snapshot = try fixture.database.removeConversationData(removal, handle: fixture.handle)
  #expect(snapshot.handle != fixture.handle)
  #expect(snapshot.page.entries.isEmpty == (removal != .learnedMemories))
  #expect(
    try fixture.database.memoryPage(.init(handle: snapshot.handle)).facts.isEmpty
      == (removal != .messages))
  #expect(try fixture.database.personalFacts(snapshot.handle).facts.count == 1)
  if removal != .learnedMemories {
    #expect(throws: ConversationStorageError.messageUnavailable) {
      try fixture.database.page(.init(handle: snapshot.handle, position: .around(message.id)))
    }
  }
  #expect(throws: ConversationStorageError.changed) {
    try fixture.database.page(.init(handle: fixture.handle, position: .around(message.id)))
  }
  #expect(throws: ConversationStorageError.changed) {
    try fixture.database.undoMemory(fixture.handle, receiptID: receipt.id)
  }
  #expect(throws: ConversationStorageError.changed) {
    try fixture.database.save(
      .init(handle: fixture.handle, messages: [message], checkpoint: .init(), savedAt: Date()))
  }
}

@Test func personalFactsUpgradeVersionFiveWithoutChangingConversationData() async throws {
  let fixture = try PersonalFactsFixture()
  defer { fixture.remove() }
  let message = ChatMessage(role: .user, text: "Keep this message")
  try fixture.database.save(
    .init(
      handle: fixture.handle, messages: [message], checkpoint: .init(draft: "Draft"),
      savedAt: Date()))
  try fixture.database.sql.execute("DROP TABLE personal_facts")
  try fixture.database.sql.execute("DROP TABLE personal_fact_state")
  try fixture.database.sql.execute("PRAGMA user_version=5")
  let reopened = try ConversationDatabase(directory: fixture.directory)
  let snapshot = try reopened.open(.init(id: "pogo", name: "Pogo"))
  #expect(snapshot.handle == fixture.handle)
  #expect(snapshot.page.entries.first?.message == message)
  #expect(snapshot.checkpoint.draft == "Draft")
  #expect(try reopened.personalFacts(snapshot.handle).facts.isEmpty)
}

private struct PersonalFactsFixture {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let database: ConversationDatabase
  let handle: ConversationHandle
  init() throws {
    database = try ConversationDatabase(directory: directory)
    handle = try database.open(.init(id: "pogo", name: "Pogo")).handle
  }
  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
}
