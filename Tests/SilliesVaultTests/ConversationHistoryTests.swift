import Foundation
import SilliesCore
import Testing

@testable import SilliesVault

@Test func conversationHistoryResumesDraftAndEvidenceWithoutLoadingTheArchive() async throws {
  let fixture = ConversationFixture()
  defer { fixture.remove() }
  let store = ConversationLibrary(directory: fixture.directory)
  let opened = try await store.open(.init(id: "pogo", name: "Pogo"))
  let messages = (0..<180).map { ChatMessage(role: .user, text: "Thought \($0)") }
  let checkpoint = ConversationCheckpoint(
    memory: .init(summary: "Working on a garden.", throughMessageID: messages[100].id),
    draft: "Tomorrow I want to", language: "fr", readingMessageID: messages[150].id)
  try await store.save(
    .init(handle: opened.handle, messages: messages, checkpoint: checkpoint, savedAt: fixture.date))
  let expectedMemory = try await store.checkpoint(opened.handle)
  #expect(
    try await store.advanceCheckpoint(
      .init(
        handle: opened.handle, expected: expectedMemory, replacement: checkpoint.memory)))
  let reopened = try await ConversationLibrary(directory: fixture.directory).open(
    .init(id: "pogo", name: "Pogo"))
  #expect(reopened.checkpoint.memory == checkpoint.memory)
  #expect(reopened.checkpoint.draft == checkpoint.draft)
  #expect(reopened.checkpoint.language == checkpoint.language)
  #expect(reopened.checkpoint.readingMessageID == checkpoint.readingMessageID)
  #expect(reopened.page.entries.count == ConversationPageRequest.defaultLimit)
  #expect(reopened.page.entries.last?.message.text == "Thought 179")
  #expect(reopened.page.hasOlder)
  let first = try #require(reopened.page.entries.first)
  let older = try await store.page(.init(handle: opened.handle, position: .before(first.sequence)))
  #expect(Set(older.entries.map(\.id)).isDisjoint(with: reopened.page.entries.map(\.id)))
  #expect(older.entries.last?.message.text == "Thought 119")
  let preceding = try await store.page(
    .init(handle: opened.handle, position: .beforeMessage(first.id)))
  #expect(preceding.entries.map(\.id) == older.entries.map(\.id))
  #expect(preceding.hasOlder && preceding.hasNewer)
  await #expect(throws: ConversationStorageError.self) {
    _ = try await store.page(.init(handle: opened.handle, position: .beforeMessage(UUID())))
  }
  let headers = try await store.conversations()
  #expect(headers.first?.messageCount == 180)
}

@Test func conversationClearingInvalidatesLateWritesAndSearch() async throws {
  let fixture = ConversationFixture()
  defer { fixture.remove() }
  let store = ConversationLibrary(directory: fixture.directory)
  let opened = try await store.open(.init(id: "pogo", name: "Pogo"))
  let message = ChatMessage(role: .user, text: "Plan a café in București")
  let update = ConversationUpdate(
    handle: opened.handle, messages: [message], checkpoint: .init(), savedAt: fixture.date)
  try await store.save(update)
  #expect(try await store.search(.init(companionID: "pogo", query: "Bucuresti")).count == 1)
  #expect(try await store.search(.init(companionID: "bolt", query: "Bucuresti")).isEmpty)
  #expect(
    try await store.search(
      .init(companionID: "pogo", query: "Bucuresti", excludingMessageID: message.id)
    ).isEmpty)
  let cleared = try await store.clear(opened.handle)
  #expect(cleared.handle != opened.handle)
  #expect(cleared.page.entries.isEmpty)
  await #expect(throws: ConversationStorageError.self) { try await store.save(update) }
  #expect(try await store.search(.init(query: "Bucuresti")).isEmpty)
}

@Test func conversationSearchPreservesRelevanceScopeExclusionsAndRecency() async throws {
  let fixture = ConversationFixture()
  defer { fixture.remove() }
  let store = ConversationLibrary(directory: fixture.directory)
  let pogo = try await store.open(.init(id: "pogo", name: "Pogo"))
  let bolt = try await store.open(.init(id: "bolt", name: "Bolt"))
  let strongest = ChatMessage(role: .user, text: "quartz cerulean")
  let older = ChatMessage(role: .user, text: "quartz")
  let newer = ChatMessage(role: .user, text: "quartz")
  let weaker = ChatMessage(role: .user, text: "quartz " + String(repeating: "other ", count: 50))
  let otherOwner = ChatMessage(role: .user, text: "quartz cerulean")
  try await store.save(
    .init(
      handle: pogo.handle, messages: [strongest, older, newer, weaker], checkpoint: .init(),
      savedAt: fixture.date))
  try await store.save(
    .init(
      handle: bolt.handle, messages: [otherOwner], checkpoint: .init(), savedAt: fixture.date))
  let scoped = try await store.search(.init(companionID: "pogo", query: "quartz cerulean"))
  #expect(scoped.map(\.entry.id) == [strongest.id, newer.id, older.id, weaker.id])
  #expect(scoped.allSatisfy { $0.owner.id == "pogo" && $0.owner.name == "Pogo" })
  let limited = try await store.search(
    .init(companionID: "pogo", query: "quartz cerulean", limit: 2, excludingMessageID: strongest.id)
  )
  #expect(limited.map(\.entry.id) == [newer.id, older.id])
  let global = try await store.search(.init(query: "quartz cerulean", limit: 2))
  #expect(global.map(\.entry.id) == [otherOwner.id, strongest.id])
  #expect(global.map(\.owner.id) == ["bolt", "pogo"])

  try await store.save(
    .init(
      handle: pogo.handle, messages: [older.withText("marigold")], checkpoint: .init(),
      removedMessageIDs: [newer.id], savedAt: fixture.date))
  let edited = try await store.search(.init(companionID: "pogo", query: "marigold"))
  #expect(edited.map(\.entry.id) == [older.id])
  #expect(edited.first?.entry.message.text == "marigold")
  let remaining = try await store.search(.init(companionID: "pogo", query: "quartz cerulean"))
  #expect(remaining.map(\.entry.id) == [strongest.id, weaker.id])
}

@Test func conversationMemoriesRequireUserProvenanceAndUndoRestoresPreviousValue() async throws {
  let fixture = ConversationFixture()
  defer { fixture.remove() }
  let store = ConversationLibrary(directory: fixture.directory)
  let opened = try await store.open(.init(id: "pogo", name: "Pogo"))
  let first = ChatMessage(role: .user, text: "My name is Alex.")
  let correction = ChatMessage(role: .user, text: "Please call me Sam instead.")
  let assistant = ChatMessage(role: .companion, text: "Your birthday is June 2.")
  try await store.save(
    .init(
      handle: opened.handle, messages: [first, correction, assistant], checkpoint: .init(),
      savedAt: fixture.date))
  let original = try await store.remember(
    .init(
      handle: opened.handle, fact: .init(key: "name", value: "Alex"),
      source: .init(messageID: first.id, quote: first.text), savedAt: fixture.date))
  let changed = try await store.remember(
    .init(
      handle: opened.handle, fact: .init(key: "name", value: "Sam"),
      source: .init(messageID: correction.id, quote: correction.text), savedAt: fixture.date
    ).replacing(original.saved.reference))
  #expect(
    try await store.memories(
      .init(handle: opened.handle, text: "Sam", limit: CompanionMemoryQuery.maximumResults)
    ).first?.value == "Sam")
  await #expect(throws: ConversationStorageError.self) {
    try await store.remember(
      .init(
        handle: opened.handle, fact: .init(key: "birthday", value: "June 2"),
        source: .init(messageID: assistant.id, quote: assistant.text), savedAt: fixture.date))
  }
  let undone = try await store.undoMemory(opened.handle, receiptID: changed.id)
  #expect(
    try await store.memories(
      .init(handle: undone.handle, text: "", limit: CompanionMemoryQuery.maximumResults)
    ).first?.value == "Alex")
  #expect(undone.handle != opened.handle)
  let fact = try #require(
    try await store.memories(
      .init(handle: undone.handle, text: "", limit: CompanionMemoryQuery.maximumResults)
    ).first)
  let forgotten = try await store.forget(undone.handle, id: fact.id)
  #expect(
    try await store.memories(
      .init(handle: forgotten.handle, text: "", limit: CompanionMemoryQuery.maximumResults)
    ).isEmpty)
  #expect(try await store.recentMemoryChanges(forgotten.handle).isEmpty)
  #expect(forgotten.checkpoint.memory.summary.isEmpty)
}

private struct ConversationFixture {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let date = Date(timeIntervalSince1970: 1_793_534_400)
  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch {
      Issue.record("Conversation fixture cleanup: \(error)")
    }
  }
}

@Test func memorySourcesKeepLongUserMessagesAndLargeUndoReceiptsReadable() async throws {
  let fixture = ConversationFixture()
  defer { fixture.remove() }
  let store = ConversationLibrary(directory: fixture.directory)
  let opened = try await store.open(.init(id: "pogo", name: "Pogo"))
  let padding = String(repeating: "👩🏽‍💻", count: 1_050) + String(repeating: "\"", count: 200)
  let first = ChatMessage(role: .user, text: padding + " My name is Alex.")
  let correction = ChatMessage(role: .user, text: padding + " Call me Sam instead.")
  #expect(first.text.utf8.count <= ChatContext.maximumMessageBytes)
  try await store.save(
    .init(
      handle: opened.handle, messages: [first, correction], checkpoint: .init(),
      savedAt: fixture.date))
  let original = try await store.remember(
    .init(
      handle: opened.handle, fact: .init(key: "name", value: "Alex"),
      source: .init(messageID: first.id, quote: first.text), savedAt: fixture.date))
  let updated = try await store.remember(
    .init(
      handle: opened.handle, fact: .init(key: "name", value: "Sam"),
      source: .init(messageID: correction.id, quote: correction.text), savedAt: fixture.date
    ).replacing(original.saved.reference))
  #expect(try JSONEncoder().encode(updated).count > 32_768)
  let reopened = ConversationLibrary(directory: fixture.directory)
  let receipts = try await reopened.recentMemoryChanges(opened.handle)
  #expect(receipts.count == 2)
  #expect(receipts.first?.saved.sourceQuote == correction.text)
  let snapshot = try await reopened.undoMemory(opened.handle, receiptID: updated.id)
  #expect(
    try await reopened.memories(
      .init(handle: snapshot.handle, text: "name", limit: CompanionMemoryQuery.maximumResults)
    ).first?.sourceQuote == first.text)
}
