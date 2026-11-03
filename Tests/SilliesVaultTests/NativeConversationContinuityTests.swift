import Foundation
import SilliesCore
import SilliesModelStore
import SilliesTextModels
import Testing

@testable import SilliesReasoning
@testable import SilliesVault

/// Opt-in, bounded native control. Synthetic storage only; no model downloads or app settings.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_CONTINUITY_MODEL"] != nil))
func nativeLongHistoryAndCheckpointPreemption() async throws {
  let fixture = ConversationContinuityFixture()
  defer { fixture.remove() }
  let model = try await NativeConversationModel.prepare()
  let backend = NativeContinuityTrace(base: model.backend)
  let lifetime = TextModelLifetime()
  let result: Result<Void, Error>
  do {
    await model.backend.retain(for: lifetime)
    let store = fixture.library
    let handle = try await fixture.seed(10_000, in: store)
    let context = try await fixture.question(
      "Say hello in one short sentence.", handle: handle, store: store, session: lifetime.id)
    let gate = ReasoningTurnGate()
    let service = LocalConversationService(
      resolveBackend: { backend }, tools: [], turns: gate, history: .init(repository: store))
    let first = ContinuousClock.now
    let reply = try await service.reply(to: context)
    #expect(!reply.text.isEmpty)
    #expect(await backend.summaries == 0)
    print(
      "NATIVE CONTINUITY \(model.id): 10001 messages; reply=\(first.duration(to: .now)); text=\(reply.text)"
    )

    let maintenance = ConversationCheckpointMaintenance(
      repository: store, resolveBackend: { backend }, turns: gate,
      schedule: .init(idleDelay: .zero, sliceDeadline: .seconds(30)))
    await maintenance.retain(for: lifetime)
    let began = await backend.started.stream
    await maintenance.enqueue(context)
    for await _ in began { break }
    // The preceding reply warmed the helper. Allow native prefill to begin before interruption.
    try await Task.sleep(for: .milliseconds(200))
    let interruption = ContinuousClock.now
    try await gate.acquire(.interactive)
    let acquired = interruption.duration(to: .now)
    await gate.release()
    await lifetime.end()
    #expect(acquired < .seconds(5))
    #expect(await backend.cancelledSummaries >= 1)
    let resumed = ContinuousClock.now
    let after = try await service.reply(to: context)
    #expect(!after.text.isEmpty)
    print(
      "NATIVE CONTINUITY \(model.id): preemption=\(acquired); resumed reply=\(resumed.duration(to: .now)); text=\(after.text)"
    )
    let checkpointStart = ContinuousClock.now
    let job = try #require(ConversationCheckpointJob(context))
    let advanced = try await advanceNativeCheckpoint(
      .init(repository: store, backend: backend), job: job)
    #expect(advanced)
    let restarted = try await fixture.library.open(.init(id: "pogo", name: "Pogo"))
    #expect(restarted.checkpoint.memory.throughMessageID != nil)
    #expect(!restarted.checkpoint.memory.summary.isEmpty)
    print(
      "NATIVE CONTINUITY \(model.id): persisted checkpoint=\(checkpointStart.duration(to: .now)); summary=\(restarted.checkpoint.memory.summary)"
    )
    result = .success(())
  } catch { result = .failure(error) }
  await lifetime.end()
  await model.stop()
  try result.get()
}

private enum NativeCheckpointDeadline: Error { case exceeded }

private func advanceNativeCheckpoint(
  _ worker: ConversationCheckpointWorker, job: ConversationCheckpointJob
) async throws -> Bool {
  try await withThrowingTaskGroup(of: Bool.self) { group in
    group.addTask { try await worker.advance(job) }
    group.addTask {
      try await Task.sleep(for: .seconds(30))
      throw NativeCheckpointDeadline.exceeded
    }
    defer { group.cancelAll() }
    guard let advanced = try await group.next() else { throw CancellationError() }
    return advanced
  }
}

private actor NativeContinuityTrace: ConversationBackend {
  let base: any ConversationBackend
  nonisolated var contextWindowTokens: Int { base.contextWindowTokens }
  nonisolated var conversationPolicy: ConversationPolicy { base.conversationPolicy }
  nonisolated var generationProfile: TextGenerationProfile { base.generationProfile }
  nonisolated var toolResultBudgeting: ConversationToolResultBudgeting { base.toolResultBudgeting }
  private(set) var summaries = 0
  private(set) var cancelledSummaries = 0
  let started = AsyncStream<Void>.makeStream()
  init(base: any ConversationBackend) { self.base = base }
  func availabilityNotice(localeIdentifier: String?) async -> String? {
    await base.availabilityNotice(localeIdentifier: localeIdentifier)
  }
  func inputTokenCount(_ request: TextGenerationRequest) async throws -> Int {
    try await base.inputTokenCount(request)
  }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> String {
    summaries += 1
    started.continuation.yield(())
    do { return try await base.generate(request, format: format) } catch {
      if Task.isCancelled { cancelledSummaries += 1 }
      throw error
    }
  }
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) async throws -> String
  {
    try await base.converse(request, tools: tools)
  }
  func streamConversation(
    _ request: TextGenerationRequest, tools: ConversationToolbox,
    receive: @escaping TextDeltaSink
  ) async throws -> String {
    try await base.streamConversation(request, tools: tools, receive: receive)
  }
}
