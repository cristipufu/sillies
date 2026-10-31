import Foundation

/// Speech preempts heavyweight text inference. A text job releases its worker before speech proceeds.
package actor InferenceActivity {
  package static let shared = InferenceActivity()
  private var speechCount = 0
  private var text: (id: UUID, cancel: @Sendable () -> Void)?
  private var speechWaiters: [CheckedContinuation<Void, Never>] = []
  private var idleWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

  package init() {}

  package func beginSpeech() async {
    speechCount += 1
    guard let text else { return }
    text.cancel()
    await withCheckedContinuation { speechWaiters.append($0) }
  }

  package func endSpeech() {
    speechCount = max(0, speechCount - 1)
    if speechCount == 0 {
      let waiters = idleWaiters.values
      idleWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
    }
  }

  package func waitForSpeech() async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      guard speechCount > 0 else { return }
      try await withCheckedThrowingContinuation { idleWaiters[id] = $0 }
    } onCancel: {
      Task { await self.cancelWaiter(id) }
    }
  }

  package func claimText(_ id: UUID, cancel: @escaping @Sendable () -> Void) -> Bool {
    guard speechCount == 0, text == nil else { return false }
    text = (id, cancel)
    return true
  }

  package func releaseText(_ id: UUID) {
    guard text?.id == id else { return }
    text = nil
    let waiters = speechWaiters
    speechWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }

  private func cancelWaiter(_ id: UUID) {
    idleWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
  }
}
