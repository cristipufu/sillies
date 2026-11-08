import Foundation
import SilliesChat
import SilliesCore
import SilliesReasoning
import SilliesVault
import Testing

@testable import SilliesApp

@Test @MainActor func conversationReopeningWaitsForItsFinalSaveAndRetainsTheDraft() async throws {
  let fixture = ReopeningFixture()
  defer { removeTestFile(at: fixture.directory) }
  try await fixture.openAndBeginClosing()
  var reopened: ChatSession?
  let failure = fixture.coordinator.openConversation(for: fixture.owner) { reopened = $0 }
  #expect(failure == nil && reopened == nil)
  #expect(fixture.session.phase == .finished)
  await fixture.repository.releaseSave()
  try await waitForReopening { reopened != nil }
  #expect(reopened === fixture.session)
  #expect(fixture.session.phase == .ready)
  #expect(fixture.session.draft == "Keep my unfinished thought")
  #expect(fixture.opens == ["pogo", "pogo"])
  await fixture.coordinator.shutdown()
  let saved = try await fixture.repository.open(fixture.owner)
  #expect(saved.checkpoint.draft == "Keep my unfinished thought")
}

@Test @MainActor func stoppingTheCrewCancelsAConversationReopenWaitingForPersistence() async throws
{
  let fixture = ReopeningFixture()
  defer { removeTestFile(at: fixture.directory) }
  try await fixture.openAndBeginClosing()
  var navigated = false
  #expect(
    fixture.coordinator.openConversation(for: fixture.owner) { _ in navigated = true } == nil)
  fixture.coordinator.stopAll()
  await fixture.repository.releaseSave()
  await fixture.coordinator.shutdown()
  #expect(!navigated && fixture.opens == ["pogo"])
  #expect(fixture.coordinator.activeChatSession == nil)
}

@MainActor private final class ReopeningFixture {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let owner = ConversationOwner(id: "pogo", name: "Pogo")
  let repository: HeldConversationSave
  let session: ChatSession
  let coordinator: SkillCoordinator
  var opens: [String] = []

  init() {
    let store = ConversationLibrary(directory: directory)
    repository = HeldConversationSave(store: store)
    session = ChatWindowFixture.makeReadySession(
      conversation: ReopeningReply(), history: .stored(conversations: repository, memories: store),
      owner: owner)
    coordinator = SkillCoordinator(vault: SessionVaultStore(directory: directory))
    coordinator.makeChatSession = { [session] _, _ in
      session.resume()
      return session
    }
    coordinator.onOpenChatSession = { [weak self] in self?.opens.append($0.companionID) }
  }

  func openAndBeginClosing() async throws {
    #expect(coordinator.startConversation(.chat, for: owner.id, name: owner.name) == nil)
    await session.restoreHistory()
    session.draft = "Keep my unfinished thought"
    await repository.holdNextSave()
    coordinator.stopSkill(for: owner.id)
    try await waitForReopening { await self.repository.isWaiting }
  }
}

@MainActor private func waitForReopening(_ condition: () async -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while !(await condition()), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(await condition())
}

private struct ReopeningReply: ConversationResponding {
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  { .init(text: "Hello") }
}

private actor HeldConversationSave: ConversationRepository {
  let store: ConversationLibrary
  private var holdsNextSave = false
  private var continuation: CheckedContinuation<Void, Never>?
  var isWaiting: Bool { continuation != nil }
  init(store: ConversationLibrary) { self.store = store }
  func holdNextSave() { holdsNextSave = true }
  func releaseSave() {
    continuation?.resume()
    continuation = nil
  }
  func save(_ update: ConversationUpdate) async throws {
    if holdsNextSave {
      holdsNextSave = false
      await withCheckedContinuation { continuation = $0 }
    }
    try await store.save(update)
  }
  func open(_ owner: ConversationOwner) async throws -> ConversationSnapshot {
    try await store.open(owner)
  }
  func page(_ request: ConversationPageRequest) async throws -> ConversationPage {
    try await store.page(request)
  }
  func checkpoint(_ handle: ConversationHandle) async throws -> ConversationMemorySnapshot {
    try await store.checkpoint(handle)
  }
  func advanceCheckpoint(_ update: ConversationMemoryUpdate) async throws -> Bool {
    try await store.advanceCheckpoint(update)
  }
  func search(_ request: ConversationSearchRequest) async throws -> [ConversationSearchMatch] {
    try await store.search(request)
  }
  func conversations() async throws -> [ConversationHeader] { try await store.conversations() }
  func clear(_ handle: ConversationHandle) async throws -> ConversationSnapshot {
    try await store.clear(handle)
  }
}
