import AppKit
import SilliesChat
import SilliesCore
import SilliesVault
import Synchronization
import Testing

@testable import SilliesApp

@Test @MainActor func conversationExportCancellationDrainsThroughTheModalRunLoop() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let store = ConversationLibrary(directory: directory)
  let probe = HeldConversationExport(store: store)
  let history = ChatHistory(configuration: .stored(conversations: probe, memories: store))
  _ = try await history.load(.init(id: "pogo", name: "Pogo"))
  let model = ConversationExport(
    history: history, companionName: "Pogo", deliver: MainRunLoopDelivery.perform)
  model.start(to: directory.appendingPathComponent("export.md"))
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while !(await probe.isWaiting), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(await probe.isWaiting)
  var completed = false
  model.finish { completed = true }
  #expect(!completed && model.isExporting)
  // Simulate AppKit termination without displaying a modal window or running MainActor Tasks.
  let release = Task.detached { await probe.release() }
  drainModalUntil { completed }
  #expect(completed && !model.isExporting)
  #expect(model.notice != nil)
  await release.value
  await withCheckedContinuation { continuation in
    history.stopAndFlush(deliver: MainRunLoopDelivery.perform) { continuation.resume() }
  }
}

@MainActor private func drainModalUntil(_ completed: () -> Bool) {
  let mode = CFRunLoopMode("NSModalPanelRunLoopMode" as CFString)
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while !completed(), ContinuousClock.now < deadline { CFRunLoopRunInMode(mode, 0.01, true) }
}

private actor HeldConversationExport: ConversationRepository, ConversationExporting {
  let store: ConversationLibrary
  private var continuation: CheckedContinuation<Void, Never>?
  var isWaiting: Bool { continuation != nil }
  init(store: ConversationLibrary) { self.store = store }
  func release() {
    continuation?.resume()
    continuation = nil
  }
  func exportConversation(
    _ request: ConversationExportRequest, to destination: URL,
    progress: @escaping @Sendable (Int) async -> Void
  ) async throws -> Int {
    await withCheckedContinuation { continuation = $0 }
    await progress(1)
    try Task.checkCancellation()
    return 1
  }
  func open(_ owner: ConversationOwner) async throws -> ConversationSnapshot {
    try await store.open(owner)
  }
  func save(_ update: ConversationUpdate) async throws { try await store.save(update) }
  func page(_ request: ConversationPageRequest) async throws -> ConversationPage {
    try await store.page(request)
  }
  func search(_ request: ConversationSearchRequest) async throws -> [ConversationSearchMatch] {
    try await store.search(request)
  }
  func checkpoint(_ handle: ConversationHandle) async throws -> ConversationMemorySnapshot {
    try await store.checkpoint(handle)
  }
  func advanceCheckpoint(_ update: ConversationMemoryUpdate) async throws -> Bool {
    try await store.advanceCheckpoint(update)
  }
  func conversations() async throws -> [ConversationHeader] { try await store.conversations() }
  func clear(_ handle: ConversationHandle) async throws -> ConversationSnapshot {
    try await store.clear(handle)
  }
}
