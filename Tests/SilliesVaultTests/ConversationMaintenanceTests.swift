import Foundation
import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning
@testable import SilliesVault

@Test func interactiveReplyPreemptsCheckpointAndLifetimeEndStopsTheProducer() async throws {
  let fixture = ConversationContinuityFixture()
  defer { fixture.remove() }
  let store = fixture.library
  let handle = try await fixture.seed(100, in: store)
  let lifetime = TextModelLifetime()
  let context = try await fixture.question(
    "Continue", handle: handle, store: store, session: lifetime.id)
  let backend = ContinuityBackend(.waiting)
  let gate = ReasoningTurnGate()
  let maintenance = ConversationCheckpointMaintenance(
    repository: store, resolveBackend: { backend }, turns: gate,
    schedule: .init(idleDelay: .milliseconds(5), sliceDeadline: .seconds(10)))
  await maintenance.retain(for: lifetime)
  let began = await backend.started.stream
  await maintenance.enqueue(context)
  for await _ in began { break }
  let before = ContinuousClock.now
  let mainActorResponded = await MainActor.run { true }
  #expect(mainActorResponded)
  let service = LocalConversationService(
    resolveBackend: { backend }, tools: [], turns: gate,
    history: .init(repository: store))
  let reply = try await service.reply(to: context)
  let elapsed = before.duration(to: .now)
  #expect(reply.text == "Ready to continue.")
  #expect(await backend.cancelledSummaries == 1)
  #expect(elapsed < .seconds(1))
  await lifetime.end()
  let calls = await backend.summaryCalls
  try await Task.sleep(for: .milliseconds(25))
  #expect(await maintenance.pendingConversationCount == 0)
  #expect(await backend.summaryCalls == calls)
  #expect(try await store.checkpoint(handle).memory.throughMessageID == nil)
  print("CONTINUITY PREEMPTION: \(elapsed)")
}

@Test func checkpointDeadlineLeavesArchiveAndMemoryRecoverable() async throws {
  let fixture = ConversationContinuityFixture()
  defer { fixture.remove() }
  let store = fixture.library
  let handle = try await fixture.seed(40, in: store)
  let lifetime = TextModelLifetime()
  let context = try await fixture.question(
    "Continue", handle: handle, store: store, session: lifetime.id)
  let before = try await store.checkpoint(handle)
  let backend = ContinuityBackend(.waiting)
  let maintenance = ConversationCheckpointMaintenance(
    repository: store, resolveBackend: { backend }, turns: .init(),
    schedule: .init(idleDelay: .zero, sliceDeadline: .milliseconds(250)))
  await maintenance.retain(for: lifetime)
  let began = await backend.started.stream
  await maintenance.enqueue(context)
  for await _ in began { break }
  try await Task.sleep(for: .milliseconds(350))
  #expect(await backend.cancelledSummaries == 1)
  #expect(try await store.checkpoint(handle) == before)
  #expect(try await store.conversations().first?.messageCount == 41)
  await lifetime.end()
}

@Test func queuedCheckpointRequestsCoalesceAndCannotRestartAfterClosing() async throws {
  let fixture = ConversationContinuityFixture()
  defer { fixture.remove() }
  let store = fixture.library
  let handle = try await fixture.seed(40, in: store)
  let lifetime = TextModelLifetime()
  let context = try await fixture.question(
    "Continue", handle: handle, store: store, session: lifetime.id)
  let backend = ContinuityBackend()
  let gate = ReasoningTurnGate()
  try await gate.acquire(.interactive)
  let maintenance = ConversationCheckpointMaintenance(
    repository: store, resolveBackend: { backend }, turns: gate,
    schedule: .init(idleDelay: .milliseconds(10), sliceDeadline: .seconds(1)))
  await maintenance.retain(for: lifetime)
  for _ in 0..<1_000 { await maintenance.enqueue(context) }
  #expect(await maintenance.pendingConversationCount <= 1)
  await lifetime.end()
  await maintenance.enqueue(context)
  await gate.release()
  try await Task.sleep(for: .milliseconds(30))
  #expect(await backend.summaryCalls == 0)
  #expect(await maintenance.pendingConversationCount == 0)
}
