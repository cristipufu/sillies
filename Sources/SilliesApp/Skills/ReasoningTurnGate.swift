import Foundation
import SilliesTextModels

/// Bounded, cancellation-aware queue. Interactive writing goes before waiting background notes.
actor ReasoningTurnGate {
  enum Priority { case background, interactive }
  private struct Waiter {
    let id: UUID
    let continuation: CheckedContinuation<Void, Error>
  }
  private static let maximumWaiters = 8
  private var occupied = false
  private var waiters: [Waiter] = []

  func tryAcquire() -> Bool {
    guard !occupied else { return false }
    occupied = true
    return true
  }
  func acquire(_ priority: Priority) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      if tryAcquire() { return }
      guard waiters.count < Self.maximumWaiters else { throw TextModelError.busy }
      try await withCheckedThrowingContinuation { continuation in
        let waiter = Waiter(id: id, continuation: continuation)
        switch priority {
        case .interactive: waiters.insert(waiter, at: 0)
        case .background: waiters.append(waiter)
        }
      }
    } onCancel: {
      Task { await self.cancel(id) }
    }
  }
  func release() {
    if waiters.isEmpty { occupied = false } else { waiters.removeFirst().continuation.resume() }
  }
  private func cancel(_ id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
    waiters.remove(at: index).continuation.resume(throwing: CancellationError())
  }
}
