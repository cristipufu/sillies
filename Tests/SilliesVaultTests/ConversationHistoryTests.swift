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
  let reopened = try await ConversationLibrary(directory: fixture.directory).open(
    .init(id: "pogo", name: "Pogo"))
  #expect(reopened.checkpoint == checkpoint)
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
  let cleared = try await store.clear(opened.handle)
  #expect(cleared.handle != opened.handle)
  #expect(cleared.page.entries.isEmpty)
  await #expect(throws: ConversationStorageError.self) { try await store.save(update) }
  #expect(try await store.search(.init(query: "Bucuresti")).isEmpty)
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
  _ = try await store.remember(
    .init(
      handle: opened.handle, fact: .init(key: "name", value: "Alex"),
      source: .init(messageID: first.id, quote: first.text), savedAt: fixture.date))
  let changed = try await store.remember(
    .init(
      handle: opened.handle, fact: .init(key: "name", value: "Sam"),
      source: .init(messageID: correction.id, quote: correction.text), savedAt: fixture.date))
  #expect(try await store.memories(opened.handle, query: "Sam").first?.value == "Sam")
  await #expect(throws: ConversationStorageError.self) {
    try await store.remember(
      .init(
        handle: opened.handle, fact: .init(key: "birthday", value: "June 2"),
        source: .init(messageID: assistant.id, quote: assistant.text), savedAt: fixture.date))
  }
  let undone = try await store.undoMemory(opened.handle, receiptID: changed.id)
  #expect(try await store.memories(undone.handle, query: "").first?.value == "Alex")
  #expect(undone.handle != opened.handle)
  let fact = try #require(try await store.memories(undone.handle, query: "").first)
  let forgotten = try await store.forget(undone.handle, id: fact.id)
  #expect(try await store.memories(forgotten.handle, query: "").isEmpty)
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
  _ = try await store.remember(
    .init(
      handle: opened.handle, fact: .init(key: "name", value: "Alex"),
      source: .init(messageID: first.id, quote: first.text), savedAt: fixture.date))
  let updated = try await store.remember(
    .init(
      handle: opened.handle, fact: .init(key: "name", value: "Sam"),
      source: .init(messageID: correction.id, quote: correction.text), savedAt: fixture.date))
  #expect(try JSONEncoder().encode(updated).count > 32_768)
  let reopened = ConversationLibrary(directory: fixture.directory)
  let receipts = try await reopened.recentMemoryChanges(opened.handle)
  #expect(receipts.count == 2)
  #expect(receipts.first?.saved.sourceQuote == correction.text)
  let snapshot = try await reopened.undoMemory(opened.handle, receiptID: updated.id)
  #expect(
    try await reopened.memories(snapshot.handle, query: "name").first?.sourceQuote == first.text)
}
