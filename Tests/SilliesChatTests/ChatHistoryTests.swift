import Foundation
import SilliesCore
import Testing

@testable import SilliesChat

@Test @MainActor func conversationHistoryRetainsFailedWritesAndRetriesTheLatestDraft() async throws
{
  let store = HistoryStorageProbe()
  let history = ChatHistory(configuration: .stored(conversations: store, memories: store))
  _ = try await history.load(.init(id: "pogo", name: "Pogo"))
  let message = ChatMessage(role: .user, text: "Please keep these words")
  history.stage(message)
  await #expect(throws: ConversationStorageError.self) { try await history.flush() }
  #expect(history.hasUnsavedChanges)
  #expect(history.failure != nil)
  history.update(.init(draft: "A newer draft"))
  await store.allowWrites()
  try await history.flush()
  #expect(!history.hasUnsavedChanges)
  #expect(history.failure == nil)
  let saved = try #require(await store.saved.last)
  #expect(saved.messages.map(\.id) == [message.id])
  #expect(saved.checkpoint.draft == "A newer draft")
  history.stopAndFlush(deliver: { action in Task { @MainActor in action() } }, completion: {})
}

private actor HistoryStorageProbe: ConversationRepository, CompanionMemoryRepository {
  private let memoryCommitted: @Sendable () -> Void
  init(memoryCommitted: @escaping @Sendable () -> Void = {}) {
    self.memoryCommitted = memoryCommitted
  }
  let handle = ConversationHandle(companionID: "pogo", generation: UUID())
  var saved: [ConversationUpdate] = []
  var memoryWrites: [MemoryWrite] = []
  private var writesAllowed = false
  private var snapshot: ConversationSnapshot {
    .init(
      handle: handle, checkpoint: .init(),
      page: .init(entries: [], hasOlder: false, hasNewer: false))
  }
  func allowWrites() { writesAllowed = true }
  func open(_ owner: ConversationOwner) -> ConversationSnapshot { snapshot }
  func save(_ update: ConversationUpdate) throws {
    guard writesAllowed else { throw ConversationStorageError.invalidData }
    saved.append(update)
  }
  func checkpoint(_ handle: ConversationHandle) -> ConversationMemorySnapshot {
    snapshot.checkpoint.memorySnapshot
  }
  func advanceCheckpoint(_ update: ConversationMemoryUpdate) -> Bool { false }
  func page(_ request: ConversationPageRequest) -> ConversationPage { snapshot.page }
  func search(_ request: ConversationSearchRequest) -> [ConversationSearchMatch] { [] }
  func conversations() -> [ConversationHeader] { [] }
  func clear(_ handle: ConversationHandle) -> ConversationSnapshot { snapshot }
  func memories(_ query: CompanionMemoryQuery) -> [CompanionMemory] { [] }
  func memoryPage(_ request: CompanionMemoryPageRequest) -> CompanionMemoryPage {
    .init(facts: [], next: nil)
  }
  func remember(_ request: MemoryWrite) throws -> MemoryReceipt {
    guard
      saved.contains(where: { $0.messages.contains(where: { $0.id == request.sourceMessageID }) })
    else { throw ConversationStorageError.invalidData }
    guard !memoryWrites.contains(where: { $0.key == request.key }) else {
      throw MemoryMutationError.keyAlreadyExists
    }
    memoryWrites.append(request)
    memoryCommitted()
    return .init(
      handle: request.handle, id: UUID(), previous: nil,
      saved: .init(
        replacing: nil, fact: request.fact, source: request.source, savedAt: request.savedAt))
  }
  func forget(_ handle: ConversationHandle, id: UUID) -> ConversationSnapshot { snapshot }
  func undoMemory(_ handle: ConversationHandle, receiptID: UUID) -> ConversationSnapshot {
    snapshot
  }
  func recentMemoryChanges(_ handle: ConversationHandle) -> [MemoryReceipt] { [] }
}

@Test @MainActor func explicitMemoryFlushesItsSourceAndPublishesAReceiptWithoutInference()
  async throws
{
  let store = HistoryStorageProbe()
  await store.allowWrites()
  let history = ChatHistory(configuration: .stored(conversations: store, memories: store))
  _ = try await history.load(.init(id: "pogo", name: "Pogo"))
  let message = ChatMessage(role: .user, text: "I prefer short answers.")
  history.stage(message)
  let editor = ChatMemoryEditor(history: history)
  #expect(!editor.canRemember(.init(role: .companion, text: "An invented fact")))
  editor.begin(message)
  editor.topic = "Answer length"
  editor.value = "I prefer concise answers."
  await editor.save()
  #expect(!editor.isPresented && editor.failure == nil)
  let saved = try #require(await store.memoryWrites.first)
  #expect(saved.value == "I prefer concise answers.")
  #expect(saved.sourceMessageID == message.id && saved.sourceQuote == message.text)
  #expect(history.memoryReceipts.count == 1)
  #expect(history.memories.page.facts.first?.value == saved.value)
  editor.begin(message)
  editor.topic = "Answer length"
  await editor.save()
  #expect(editor.isPresented && editor.failure != nil)
  #expect(await store.memoryWrites.count == 1)
  #expect(editor.value == message.text)
  editor.close()
  history.stopAndFlush(deliver: { action in Task { @MainActor in action() } }, completion: {})
}

@Test @MainActor func explicitMemoryRejectsAChangedConversationAndKeepsTheReviewedFact()
  async throws
{
  let store = HistoryStorageProbe()
  await store.allowWrites()
  let history = ChatHistory(configuration: .stored(conversations: store, memories: store))
  let snapshot = try #require(try await history.load(.init(id: "pogo", name: "Pogo")))
  let editor = ChatMemoryEditor(history: history)
  editor.begin(.init(role: .user, text: "A fact"))
  editor.topic = "Topic"
  history.restore(
    .init(
      handle: .init(companionID: "pogo", generation: UUID()),
      checkpoint: .init(), page: snapshot.page))
  await editor.save()
  #expect(editor.isPresented && editor.failure != nil)
  #expect(editor.value == "A fact")
  #expect(await store.memoryWrites.isEmpty)
  editor.close()
}

@Test @MainActor func explicitMemoryRetainsTheDraftWhenItsSourceCannotBeSaved() async throws {
  let store = HistoryStorageProbe()
  let history = ChatHistory(configuration: .stored(conversations: store, memories: store))
  _ = try await history.load(.init(id: "pogo", name: "Pogo"))
  let message = ChatMessage(role: .user, text: "I prefer short answers.")
  history.stage(message)
  let editor = ChatMemoryEditor(history: history)
  editor.begin(message)
  editor.topic = "Answer length"
  await editor.save()
  #expect(editor.isPresented && editor.failure != nil)
  #expect(editor.value == message.text)
  #expect(await store.memoryWrites.isEmpty)
  #expect(history.memoryReceipts.isEmpty)
  await store.allowWrites()
  await editor.save()
  #expect(!editor.isPresented && editor.failure == nil)
  #expect(history.memoryReceipts.count == 1)
  history.stopAndFlush(deliver: { action in Task { @MainActor in action() } }, completion: {})
}

@Test @MainActor func explicitMemoryPublishesACommittedReceiptEvenIfItsTaskIsCancelled()
  async throws
{
  let store = HistoryStorageProbe(memoryCommitted: { withUnsafeCurrentTask { $0?.cancel() } })
  await store.allowWrites()
  let history = ChatHistory(configuration: .stored(conversations: store, memories: store))
  _ = try await history.load(.init(id: "pogo", name: "Pogo"))
  let message = ChatMessage(role: .user, text: "I prefer short answers.")
  history.stage(message)
  let editor = ChatMemoryEditor(history: history)
  editor.begin(message)
  editor.topic = "Answer length"
  let saving = Task { await editor.save() }
  await saving.value
  #expect(saving.isCancelled)
  #expect(!editor.isPresented && editor.failure == nil)
  #expect(history.memoryReceipts.count == 1)
  #expect(await store.memoryWrites.count == 1)
  history.stopAndFlush(deliver: { action in Task { @MainActor in action() } }, completion: {})
}
