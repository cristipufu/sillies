import AppKit
import CoreTransferable
import SilliesChat
import SilliesCore
import SilliesReasoning
import SilliesVault
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import SilliesApp

@Test func vaultRecordTransferRoundTripsIdentityAndRejectsMalformedDrops() async throws {
  let original = VaultRecordTransfer(id: UUID())
  let data = try await original.exported(as: .silliesVaultRecord)
  let restored = try await VaultRecordTransfer(importing: data, contentType: .silliesVaultRecord)
  #expect(restored.id == original.id)
  let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
  #expect(
    fields == ["id": original.id.uuidString], "Private record contents must stay in the Vault.")
  await #expect(throws: (any Error).self) {
    _ = try await VaultRecordTransfer(
      importing: Data(#"{"id":"invalid"}"#.utf8), contentType: .silliesVaultRecord)
  }
}

@Test @MainActor func chatVaultPickerRejectsStaleRowsAndLateSearchResults() async throws {
  let old = SessionRecordHeader(
    SessionRecord(
      kind: .stash,
      origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Old"))))
  let newest = SessionRecordHeader(
    SessionRecord(
      kind: .stash,
      origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "New"))))
  let (started, signal) = AsyncStream<Void>.makeStream()
  var pending: CheckedContinuation<[SessionRecordHeader], Never>?
  let picker = ChatVaultPickerModel { query in
    if !query.isEmpty { return [newest] }
    return await withCheckedContinuation { continuation in
      pending = continuation
      signal.yield(())
    }
  }
  let first = Task { await picker.search() }
  var starts = started.makeAsyncIterator()
  _ = await starts.next()
  picker.query = "new"
  await picker.search()
  #expect(picker.records == [newest])
  pending?.resume(returning: [old])
  await first.value
  #expect(picker.records == [newest])
  picker.query = "another"
  #expect(picker.records.isEmpty, "Previous-query rows must become unselectable immediately.")
  signal.finish()
}

@Test @MainActor func explicitContextAndMemoryControlsFitChatInBothThemes() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let conversations = ConversationLibrary(directory: directory.appendingPathComponent("Chat"))
  let vault = SessionVaultStore(directory: directory.appendingPathComponent("Vault"))
  await vault.waitUntilLoaded()
  let session = ChatWindowFixture.makeReadySession(
    conversation: ContextReply(),
    history: .stored(conversations: conversations, memories: conversations),
    owner: .init(id: "pogo", name: "Pogo"),
    context: .init(materials: vault.library, personalFacts: conversations))
  await session.restoreHistory()
  for index in 1...3 {
    var record = SessionRecord(
      kind: .stash,
      origin: .init(
        characterID: "pogo", characterName: "Pogo",
        source: .init(appName: "Planning notes for the next release \(index)")))
    record.stashedItems = ["Review on Thursday at 14:00."]
    vault.add(record)
    await vault.flush()
    #expect(session.selectedRecords.add(record.id))
  }
  await vault.flush()
  await session.refreshAvailability()
  let previewDeadline = ContinuousClock.now.advanced(by: .seconds(2))
  while session.selectedRecords.isLoading, ContinuousClock.now < previewDeadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  session.personalFacts.begin()
  session.personalFacts.topic = "Preferred name"
  session.personalFacts.value = "Alex"
  await session.personalFacts.save()
  session.draft = "Compare these notes."
  for scheme in [ColorScheme.light, .dark] {
    try renderSkillInterface(
      ConversationBubbleView(
        presentation: ConversationBubblePresentation(),
        content: ChatSessionView(
          model: session, openSettings: { _ in }, close: {}, renderer: "frog", motion: .reduced,
          vault: .init(store: vault, openRecord: { _ in }))
      ).environment(\.colorScheme, scheme),
      size: ChatWindowLayout.minimumSize, name: "sillies-context-chat-\(scheme)")
    try renderSkillInterface(
      ChatPersonalFactsView(model: session.personalFacts, companionName: "Pogo")
        .padding(20).background(Color(nsColor: .windowBackgroundColor)).environment(
          \.colorScheme, scheme),
      size: .init(width: 380, height: 420), name: "sillies-pinned-facts-\(scheme)")
    try renderSkillInterface(
      ConversationMemoriesView(model: session, back: {}).environment(\.colorScheme, scheme),
      size: .init(width: 380, height: 500), name: "sillies-memories-\(scheme)")
    try renderSkillInterface(
      ConversationDataControlsView(model: session, openSettings: {})
        .padding(20).environment(\.colorScheme, scheme), size: .init(width: 380, height: 420),
      name: "sillies-memory-controls-\(scheme)")
  }
  #expect(session.draft == "Compare these notes.")
  let selected = session.selectedRecords.selection
  await withCheckedContinuation { continuation in session.finish { continuation.resume() } }
  let reopened = try await conversations.open(.init(id: "pogo", name: "Pogo"))
  #expect(reopened.checkpoint.selectedRecords == selected)
  #expect(reopened.checkpoint.draft == "Compare these notes.")
}

@Test @MainActor func pinnedFactWritesDrainInAppKitsTerminationRunLoop() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let store = ConversationLibrary(directory: directory)
  let repository = HeldPersonalFacts(store: store)
  let history = ChatHistory(configuration: .stored(conversations: store, memories: store))
  _ = try await history.load(.init(id: "pogo", name: "Pogo"))
  let model = ChatPersonalFacts(history: history, repository: repository)
  model.begin()
  model.topic = "name"
  model.value = "Alex"
  let save = Task { await model.save() }
  await repository.waitUntilSaving()
  var completed = false
  model.finish(deliver: MainRunLoopDelivery.perform) { completed = true }
  let release = Task.detached { await repository.release() }
  drainContextMutationUntil { completed }
  #expect(completed)
  await release.value
  await save.value
  let handle = try #require(history.handle)
  #expect(try await store.personalFacts(handle).facts.first?.fact.value == "Alex")
  #expect(!model.isSaving)
}

@MainActor private func drainContextMutationUntil(_ completed: () -> Bool) {
  let mode = CFRunLoopMode("NSModalPanelRunLoopMode" as CFString)
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while !completed(), ContinuousClock.now < deadline { CFRunLoopRunInMode(mode, 0.01, true) }
}

private struct ContextReply: ConversationResponding {
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  {
    .init(text: "Let's look at your notes.")
  }
}

@Test @MainActor func vaultDiscussionFailureUsesRecoveryPresentationAndNeverSuccessFeedback()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  let owner = ConversationOwner(id: "pogo", name: "Pogo")
  let failure = SessionFailure(
    category: .captureUnavailable, message: "Synthetic busy conversation")
  var calls = 0
  let model = SessionVaultModel(
    vault: vault,
    presentation: .init(
      discussion: .init(
        companions: [owner],
        open: { _, _ in
          calls += 1
          return failure
        })))
  model.discuss(UUID(), with: owner)
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while model.discussionFailure == nil, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(model.discussionFailure == failure)
  #expect(model.feedback == nil)
  model.dismissDiscussionFailure()
  #expect(model.discussionFailure == nil)
  model.stop()
  model.discuss(UUID(), with: owner)
  await vault.flush()
  #expect(calls == 1)
}

private actor HeldPersonalFacts: PersonalFactsRepository {
  let store: ConversationLibrary
  private var waiting: CheckedContinuation<Void, Never>?
  private var observer: CheckedContinuation<Void, Never>?
  init(store: ConversationLibrary) { self.store = store }
  func waitUntilSaving() async {
    if waiting != nil { return }
    await withCheckedContinuation { observer = $0 }
  }
  func release() {
    waiting?.resume()
    waiting = nil
  }
  func personalFacts(_ handle: ConversationHandle) async throws -> PersonalFactsSnapshot {
    try await store.personalFacts(handle)
  }
  func savePersonalFact(_ request: PersonalFactWrite) async throws -> PersonalFactsSnapshot {
    await withCheckedContinuation {
      waiting = $0
      observer?.resume()
      observer = nil
    }
    return try await store.savePersonalFact(request)
  }
  func removePersonalFact(_ fact: PersonalFact, handle: ConversationHandle) async throws
    -> PersonalFactsSnapshot
  {
    try await store.removePersonalFact(fact, handle: handle)
  }
}
