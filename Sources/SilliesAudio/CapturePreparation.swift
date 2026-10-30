import Foundation
import Synchronization

/// Cancels startup immediately even when the capture worker is draining queued audio.
final class CapturePreparation: Sendable {
  private enum State {
    case ready
    case running(Task<Void, Never>)
    case cancelled
  }
  private let state = Mutex(State.ready)

  func launch(_ operation: @escaping @Sendable () async -> Void) {
    state.withLock {
      guard case .ready = $0 else { return }
      $0 = .running(Task.detached(priority: .utility, operation: operation))
    }
  }

  func cancel() {
    let task = state.withLock { state -> Task<Void, Never>? in
      defer { state = .cancelled }
      guard case .running(let task) = state else { return nil }
      return task
    }
    task?.cancel()
  }
}
