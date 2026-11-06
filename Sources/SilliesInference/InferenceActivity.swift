import Foundation
import SilliesDiagnostics

/// Microphone recognition preempts synthesis; interactive synthesis preempts background text work.
package actor InferenceActivity {
  package static let shared = InferenceActivity()
  private var speechCount = 0
  private var diagnostics: DiagnosticSink
  private struct Work {
    enum Kind { case generation, preparation }
    let id: UUID
    let reservation: InferenceReservation
    let cancel: @Sendable () -> Void
    var kind = Kind.generation
  }
  private var text: Work?
  private var synthesis: Work?
  private var embedding: Work?
  private var interactiveCount = 0
  private var embeddingDrainWaiters: [CheckedContinuation<Void, Never>] = []
  package enum EmbeddingPriority: Sendable { case query, background }
  private let overlapBudget: UInt64
  private let residency: InferenceModelResidency
  private var synthesisWaiter: CheckedContinuation<Void, Never>?
  private var speechWaiters: [CheckedContinuation<Void, Never>] = []
  private var idleWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

  package init(
    overlapBudget: UInt64 = ProcessInfo.processInfo.physicalMemory / 3 * 2,
    diagnostics: DiagnosticSink = .disabled
  ) {
    self.overlapBudget = overlapBudget
    self.diagnostics = diagnostics
    residency = InferenceModelResidency(budget: overlapBudget)
  }

  /// App composition attaches its lifetime-owned sink to the existing shared admission coordinator.
  package func setDiagnostics(_ diagnostics: DiagnosticSink) { self.diagnostics = diagnostics }

  private func preempt(_ work: Work?, because reason: DiagnosticEvent.Reason) {
    guard let work else { return }
    var event = DiagnosticEvent(.inference, .preempted, operation: work.id).because(reason)
    event.relatedOperation = work.reservation.conversationID
    diagnostics.record(event)
    work.cancel()
  }

  package func prepareTextModel(_ reservation: InferenceReservation) async {
    await residency.makeRoom(for: .text, reservation: reservation)
  }
  package func prepareVoiceModel(_ reservation: InferenceReservation) async {
    await residency.makeRoom(for: .voice, reservation: reservation)
  }
  package func prepareSearchModel(_ reservation: InferenceReservation) async {
    await residency.makeRoom(for: .search, reservation: reservation)
  }
  package func rememberSearchModel(
    id: UUID, reservation: InferenceReservation,
    evict: @escaping @Sendable () async -> Void
  ) async {
    await residency.remember(
      .search, resident: .init(id: id, bytes: reservation.bytes, evict: evict))
  }
  package func forgetSearchModel(_ id: UUID) async { await residency.forget(.search, id: id) }

  /// Search never overlaps inference. Interactive work cancels and drains its native operation.
  package func beginInteractiveWork() async {
    interactiveCount += 1
    guard let embedding else { return }
    preempt(embedding, because: .interactivePriority)
    await withCheckedContinuation { embeddingDrainWaiters.append($0) }
  }
  package func endInteractiveWork() {
    interactiveCount = max(0, interactiveCount - 1)
    resumeIdleWaiters()
  }
  package func waitForEmbeddingAdmission(_ priority: EmbeddingPriority) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      guard !canClaimEmbedding(priority) else { return }
      try await withCheckedThrowingContinuation { idleWaiters[id] = $0 }
    } onCancel: {
      Task { await self.cancelWaiter(id) }
    }
  }
  private func canClaimEmbedding(_ priority: EmbeddingPriority) -> Bool {
    speechCount == 0 && text == nil && synthesis == nil && embedding == nil
      && (priority == .query || interactiveCount == 0)
  }
  package func claimEmbedding(
    _ id: UUID, priority: EmbeddingPriority = .background,
    cancel: @escaping @Sendable () -> Void
  ) -> Bool {
    guard canClaimEmbedding(priority) else { return false }
    embedding = Work(id: id, reservation: .init(), cancel: cancel)
    return true
  }
  package func releaseEmbedding(_ id: UUID) {
    guard embedding?.id == id else { return }
    embedding = nil
    let waiters = embeddingDrainWaiters
    embeddingDrainWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
    synthesisWaiter?.resume()
    synthesisWaiter = nil
    resumeSpeechWaiters()
    resumeIdleWaiters()
  }
  package func rememberTextModel(
    id: UUID, reservation: InferenceReservation, evict: @escaping @Sendable () async -> Void
  ) async {
    await residency.remember(.text, resident: .init(id: id, bytes: reservation.bytes, evict: evict))
  }
  package func rememberVoiceModel(
    id: UUID, reservation: InferenceReservation, evict: @escaping @Sendable () async -> Void
  ) async {
    await residency.remember(
      .voice, resident: .init(id: id, bytes: reservation.bytes, evict: evict))
  }
  package func forgetTextModel(_ id: UUID) async { await residency.forget(.text, id: id) }
  package func forgetVoiceModel(_ id: UUID) async { await residency.forget(.voice, id: id) }

  package func prepareSpeechRuntime(_ prepare: @Sendable () async throws -> Void) async throws {
    await beginSpeech()
    defer { endSpeech() }
    try Task.checkCancellation()
    try await prepare()
  }

  package func beginSpeech() async {
    speechCount += 1
    preempt(text, because: .recognitionPriority)
    preempt(synthesis, because: .recognitionPriority)
    preempt(embedding, because: .recognitionPriority)
    guard text != nil || synthesis != nil || embedding != nil else { return }
    await withCheckedContinuation { speechWaiters.append($0) }
  }

  package func endSpeech() {
    speechCount = max(0, speechCount - 1)
    resumeIdleWaiters()
  }

  package func waitForBackgroundAdmission() async throws {
    try await waitForTextAdmission(.init())
  }
  package func waitForTextAdmission(_ reservation: InferenceReservation) async throws {
    preempt(embedding, because: .interactivePriority)
    let id = UUID()
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      preemptPreparation(for: reservation)
      guard !canClaimText(reservation) else { return }
      try await withCheckedThrowingContinuation { idleWaiters[id] = $0 }
    } onCancel: {
      Task { await self.cancelWaiter(id) }
    }
  }

  package func claimText(
    _ id: UUID, reservation: InferenceReservation = .init(), cancel: @escaping @Sendable () -> Void
  ) -> Bool {
    preempt(embedding, because: .interactivePriority)
    preemptPreparation(for: reservation)
    guard canClaimText(reservation) else { return false }
    text = Work(id: id, reservation: reservation, cancel: cancel)
    return true
  }

  package func releaseText(_ id: UUID) {
    guard text?.id == id else { return }
    text = nil
    synthesisWaiter?.resume()
    synthesisWaiter = nil
    resumeSpeechWaiters()
    resumeIdleWaiters()
  }

  package func claimSynthesis(
    _ id: UUID, reservation: InferenceReservation = .init(), cancel: @escaping @Sendable () -> Void
  ) async -> Bool {
    guard speechCount == 0, synthesis == nil else { return false }
    synthesis = Work(id: id, reservation: reservation, cancel: cancel)
    if let embedding {
      preempt(embedding, because: .interactivePriority)
      await withTaskCancellationHandler {
        await withCheckedContinuation { synthesisWaiter = $0 }
      } onCancel: {
        Task { await self.cancelSynthesisWaiter(id) }
      }
    }
    if let text, !reservation.canOverlap(text.reservation, budget: overlapBudget) {
      if reservation.conversationID == nil
        || reservation.conversationID != text.reservation.conversationID
      {
        preempt(text, because: .incompatibleMemory)
      }
      await withTaskCancellationHandler {
        await withCheckedContinuation { synthesisWaiter = $0 }
      } onCancel: {
        Task { await self.cancelSynthesisWaiter(id) }
      }
    }
    guard !Task.isCancelled, speechCount == 0, synthesis?.id == id else {
      releaseSynthesis(id)
      return false
    }
    return true
  }

  /// A short recognition pass may occupy the runtime before the first spoken phrase is ready.
  /// Wait without reserving synthesis so recognition can drain and retain its interactive priority.
  package func waitForSynthesisAdmission() async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      guard speechCount > 0 || synthesis != nil else { return }
      try await withCheckedThrowingContinuation { idleWaiters[id] = $0 }
    } onCancel: {
      Task { await self.cancelWaiter(id) }
    }
  }

  /// Speculation must never cancel text or reserve memory ahead of an incompatible reply.
  package func claimVoicePreparation(
    _ id: UUID, reservation: InferenceReservation, cancel: @escaping @Sendable () -> Void
  ) -> Bool {
    guard speechCount == 0, synthesis == nil, embedding == nil,
      text.map({ reservation.canOverlap($0.reservation, budget: overlapBudget) }) ?? true
    else { return false }
    synthesis = Work(id: id, reservation: reservation, cancel: cancel, kind: .preparation)
    return true
  }

  private func preemptPreparation(for reservation: InferenceReservation) {
    guard text == nil, let synthesis, synthesis.kind == .preparation,
      !reservation.canOverlap(synthesis.reservation, budget: overlapBudget)
    else { return }
    preempt(synthesis, because: .incompatibleMemory)
  }

  package func requiresTextEviction(_ id: UUID) -> Bool {
    guard let text, text.id == id, let synthesis else { return false }
    return !text.reservation.canOverlap(synthesis.reservation, budget: overlapBudget)
  }

  private func canClaimText(_ reservation: InferenceReservation) -> Bool {
    guard speechCount == 0, text == nil, embedding == nil else { return false }
    guard let synthesis else { return true }
    return reservation.canOverlap(synthesis.reservation, budget: overlapBudget)
  }

  private func cancelSynthesisWaiter(_ id: UUID) {
    guard synthesis?.id == id else { return }
    synthesisWaiter?.resume()
    synthesisWaiter = nil
  }

  package func releaseSynthesis(_ id: UUID) {
    guard synthesis?.id == id else { return }
    synthesis = nil
    resumeSpeechWaiters()
    resumeIdleWaiters()
  }

  private func resumeSpeechWaiters() {
    guard text == nil, synthesis == nil, embedding == nil else { return }
    let waiters = speechWaiters
    speechWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }

  private func resumeIdleWaiters() {
    guard speechCount == 0 else { return }
    let waiters = idleWaiters.values
    idleWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }

  private func cancelWaiter(_ id: UUID) {
    idleWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
  }
}
