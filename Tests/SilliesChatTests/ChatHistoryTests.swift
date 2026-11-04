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
  let handle = ConversationHandle(companionID: "pogo", generation: UUID())
  var saved: [ConversationUpdate] = []
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
    throw ConversationStorageError.invalidData
  }
  func forget(_ handle: ConversationHandle, id: UUID) -> ConversationSnapshot { snapshot }
  func undoMemory(_ handle: ConversationHandle, receiptID: UUID) -> ConversationSnapshot {
    snapshot
  }
  func recentMemoryChanges(_ handle: ConversationHandle) -> [MemoryReceipt] { [] }
}
