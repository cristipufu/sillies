import Foundation
import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning
@testable import SilliesVault

@Test func checkpointWriteSurvivesStalePresentationSavesAndRestart() async throws {
  let fixture = ConversationContinuityFixture()
  defer { fixture.remove() }
  let store = fixture.library
  let handle = try await fixture.seed(40, in: store)
  let initial = try await store.checkpoint(handle)
  let page = try await store.page(.init(handle: handle, position: .after(0), limit: 4))
  let memory = ConversationMemory(
    summary: "A saved decision", throughMessageID: page.entries.last?.id)
  #expect(
    try await store.advanceCheckpoint(.init(handle: handle, expected: initial, replacement: memory))
  )
  try await store.save(
    .init(
      handle: handle, messages: [], checkpoint: .init(draft: "A newer draft", language: "fr"),
      savedAt: .now))
  let restarted = try await fixture.library.open(.init(id: "pogo", name: "Pogo"))
  #expect(restarted.checkpoint.memory == memory)
  #expect(restarted.checkpoint.draft == "A newer draft")
  #expect(restarted.checkpoint.language == "fr")
  #expect(
    !(try await store.advanceCheckpoint(
      .init(
        handle: handle, expected: initial,
        replacement: .init(summary: "Late result", throughMessageID: page.entries[1].id)))))
  let current = try await store.checkpoint(handle)
  await #expect(throws: ConversationStorageError.self) {
    try await store.advanceCheckpoint(
      .init(
        handle: handle, expected: current,
        replacement: .init(summary: "Regressing cursor", throughMessageID: page.entries[1].id)))
  }
}

@Test func transcriptMutationAndClearRejectInFlightCheckpointResults() async throws {
  let fixture = ConversationContinuityFixture()
  defer { fixture.remove() }
  let store = fixture.library
  let handle = try await fixture.seed(40, in: store)
  let initial = try await store.checkpoint(handle)
  let page = try await store.page(.init(handle: handle, position: .after(0), limit: 4))
  let update = ConversationMemoryUpdate(
    handle: handle, expected: initial,
    replacement: .init(summary: "Old source", throughMessageID: page.entries.last?.id))
  try await store.save(
    .init(
      handle: handle, messages: [page.entries[0].message.withText("Corrected source")],
      checkpoint: .init(), savedAt: .now))
  #expect(!(try await store.advanceCheckpoint(update)))
  let refreshed = try await store.checkpoint(handle)
  #expect(
    try await store.advanceCheckpoint(
      .init(
        handle: handle, expected: refreshed,
        replacement: .init(summary: "Corrected source", throughMessageID: page.entries.last?.id))))
  try await store.save(
    .init(
      handle: handle, messages: [], checkpoint: .init(),
      removedMessageIDs: [page.entries[0].id], savedAt: .now))
  #expect(try await store.checkpoint(handle).memory.throughMessageID == nil)
  _ = try await store.clear(handle)
  await #expect(throws: ConversationStorageError.self) { try await store.advanceCheckpoint(update) }
}

@Test func checkpointSlicesResumeTheirCursorWithoutReplayingOlderHistory() async throws {
  let fixture = ConversationContinuityFixture()
  defer { fixture.remove() }
  var store = fixture.library
  let handle = try await fixture.seed(200, in: store)
  let context = try await fixture.question("Continue", handle: handle, store: store)
  let job = try #require(ConversationCheckpointJob(context))
  let backend = ContinuityBackend()
  var through: UUID?
  for _ in 0..<6 {
    // A new connection each time exercises durable resumption, not an in-memory cursor.
    store = fixture.library
    let previous = try await store.checkpoint(handle)
    #expect(previous.memory.throughMessageID == through)
    let reads = ConversationReadProbe(store)
    #expect(
      try await ConversationCheckpointWorker(repository: reads, backend: backend).advance(job))
    let next = try await store.checkpoint(handle)
    #expect(next.memory.throughMessageID != through)
    through = next.memory.throughMessageID
    #expect(await reads.pageReads == 1)
    #expect(
      await reads.maximumPageMessages
        <= backend.conversationPolicy.history.checkpoint.window.messageLimit)
  }
  #expect(await backend.summaryCalls == 6)
  #expect(try await store.conversations().first?.messageCount == 201)
}

@Test func failedOrCancelledSummaryNeverAdvancesItsCheckpoint() async throws {
  let fixture = ConversationContinuityFixture()
  defer { fixture.remove() }
  let store = fixture.library
  let handle = try await fixture.seed(40, in: store)
  let context = try await fixture.question("Continue", handle: handle, store: store)
  let before = try await store.checkpoint(handle)
  let job = try #require(ConversationCheckpointJob(context))
  await #expect(throws: TextModelError.self) {
    try await ConversationCheckpointWorker(repository: store, backend: ContinuityBackend(.failed))
      .advance(job)
  }
  let blocked = ContinuityBackend(.waiting)
  let started = await blocked.started.stream
  let task = Task {
    try await ConversationCheckpointWorker(repository: store, backend: blocked).advance(job)
  }
  for await _ in started { break }
  task.cancel()
  await #expect(throws: CancellationError.self) { try await task.value }
  #expect(try await store.checkpoint(handle) == before)
  #expect(try await store.conversations().first?.messageCount == 41)
}

@Test func longMessagesCanAdvanceAByteLimitedCheckpointBelowItsCountThreshold() async throws {
  let fixture = ConversationContinuityFixture()
  defer { fixture.remove() }
  let store = fixture.library
  let handle = try await fixture.seed(40, in: store)
  let originals = try await store.page(.init(handle: handle))
  let longer = originals.entries.map {
    $0.message.withText(String(repeating: "A longer discussion. ", count: 80))
  }
  try await store.save(
    .init(handle: handle, messages: longer, checkpoint: .init(), savedAt: .now))
  let context = try await fixture.question("Continue", handle: handle, store: store)
  let job = try #require(ConversationCheckpointJob(context))
  let backend = ContinuityBackend()
  let policy = backend.conversationPolicy.history.checkpoint
  let page = try await store.page(
    .init(
      handle: handle, position: .between(after: nil, before: job.beforeMessageID),
      limit: policy.window.messageLimit, maximumBytes: policy.window.byteLimit))
  #expect(page.isByteLimited)
  #expect(page.entries.count < policy.minimumMessages)
  #expect(try await ConversationCheckpointWorker(repository: store, backend: backend).advance(job))
  #expect(try await store.checkpoint(handle).memory.throughMessageID != nil)
  #expect(await backend.summaryCalls == 1)
  #expect(try await store.conversations().first?.messageCount == 41)
}
