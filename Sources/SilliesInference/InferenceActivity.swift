import Foundation

/// Microphone recognition preempts synthesis; interactive synthesis preempts background text work.
package actor InferenceActivity {
  package static let shared = InferenceActivity()
  private var speechCount = 0
  private struct Work {
    let id: UUID
    let reservation: InferenceReservation
    let cancel: @Sendable () -> Void
  }
  private var text: Work?
  private var synthesis: Work?
  private let overlapBudget: UInt64
  private let residency: InferenceModelResidency
  private var synthesisWaiter: CheckedContinuation<Void, Never>?
  private var speechWaiters: [CheckedContinuation<Void, Never>] = []
  private var idleWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

  package init(overlapBudget: UInt64 = ProcessInfo.processInfo.physicalMemory / 3 * 2) {
    self.overlapBudget = overlapBudget
    residency = InferenceModelResidency(budget: overlapBudget)
  }

  package func prepareTextModel(_ reservation: InferenceReservation) async {
    await residency.makeRoom(for: .text, reservation: reservation)
  }
  package func prepareVoiceModel(_ reservation: InferenceReservation) async {
    await residency.makeRoom(for: .voice, reservation: reservation)
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
    text?.cancel()
    synthesis?.cancel()
    guard text != nil || synthesis != nil else { return }
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
    let id = UUID()
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      guard !canClaimText(reservation) else { return }
      try await withCheckedThrowingContinuation { idleWaiters[id] = $0 }
    } onCancel: {
      Task { await self.cancelWaiter(id) }
    }
  }

  package func claimText(
    _ id: UUID, reservation: InferenceReservation = .init(), cancel: @escaping @Sendable () -> Void
  ) -> Bool {
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
    if let text, !reservation.canOverlap(text.reservation, budget: overlapBudget) {
      if reservation.conversationID == nil
        || reservation.conversationID != text.reservation.conversationID
      {
        text.cancel()
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

  package func requiresTextEviction(_ id: UUID) -> Bool {
    guard let text, text.id == id, let synthesis else { return false }
    return !text.reservation.canOverlap(synthesis.reservation, budget: overlapBudget)
  }

  private func canClaimText(_ reservation: InferenceReservation) -> Bool {
    guard speechCount == 0, text == nil else { return false }
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
    guard text == nil, synthesis == nil else { return }
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
