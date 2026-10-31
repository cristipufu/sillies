import Foundation

/// Microphone recognition preempts synthesis; interactive synthesis preempts background text work.
package actor InferenceActivity {
  package static let shared = InferenceActivity()
  private var speechCount = 0
  private var text: (id: UUID, cancel: @Sendable () -> Void)?
  private var synthesis: (id: UUID, cancel: @Sendable () -> Void)?
  private var synthesisWaiter: CheckedContinuation<Void, Never>?
  private var speechWaiters: [CheckedContinuation<Void, Never>] = []
  private var idleWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

  package init() {}

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
    let id = UUID()
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      guard speechCount > 0 || text != nil || synthesis != nil else { return }
      try await withCheckedThrowingContinuation { idleWaiters[id] = $0 }
    } onCancel: {
      Task { await self.cancelWaiter(id) }
    }
  }

  package func claimText(_ id: UUID, cancel: @escaping @Sendable () -> Void) -> Bool {
    guard speechCount == 0, text == nil, synthesis == nil else { return false }
    text = (id, cancel)
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

  package func claimSynthesis(_ id: UUID, cancel: @escaping @Sendable () -> Void) async -> Bool {
    guard speechCount == 0, synthesis == nil else { return false }
    synthesis = (id, cancel)
    if let text {
      text.cancel()
      await withCheckedContinuation { synthesisWaiter = $0 }
    }
    return true
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
    guard speechCount == 0, text == nil, synthesis == nil else { return }
    let waiters = idleWaiters.values
    idleWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }

  private func cancelWaiter(_ id: UUID) {
    idleWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
  }
}
