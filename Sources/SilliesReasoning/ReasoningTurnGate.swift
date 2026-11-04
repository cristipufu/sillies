import Foundation
import SilliesTextModels

/// Bounded, cancellation-aware queue. Interactive writing goes before waiting background notes.
package actor ReasoningTurnGate {
  package enum InteractiveActivity: Sendable { case began, ended }
  private let observeInteractive: @Sendable (InteractiveActivity) async -> Void
  private var interactiveOccupant = false
  package init(
    observeInteractive: @escaping @Sendable (InteractiveActivity) async -> Void = { _ in }
  ) {
    self.observeInteractive = observeInteractive
  }
  enum Priority { case background, interactive }
  private struct Waiter {
    let id: UUID
    let priority: Priority
    let continuation: CheckedContinuation<Void, Error>
  }
  private static let maximumWaiters = 8
  private var occupied = false
  private var waiters: [Waiter] = []
  private var cancelBackground: (@Sendable () -> Void)?

  func tryAcquire() -> Bool {
    guard !occupied else { return false }
    occupied = true
    return true
  }
  func acquire(_ priority: Priority) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      if tryAcquire() {
        interactiveOccupant = priority == .interactive
        if interactiveOccupant { await observeInteractive(.began) }
        if Task.isCancelled {
          await release()
          throw CancellationError()
        }
        return
      }
      guard waiters.count < Self.maximumWaiters else { throw TextModelError.busy }
      if priority == .interactive { cancelBackground?() }
      try await withCheckedThrowingContinuation { continuation in
        let waiter = Waiter(id: id, priority: priority, continuation: continuation)
        switch priority {
        case .interactive:
          let index = waiters.firstIndex(where: { $0.priority == .background }) ?? waiters.endIndex
          waiters.insert(waiter, at: index)
        case .background: waiters.append(waiter)
        }
      }
      // Cancellation can race with release after this waiter has already been granted ownership.
      if Task.isCancelled {
        await release()
        throw CancellationError()
      }
    } onCancel: {
      Task { await self.cancel(id) }
    }
  }
  func performCheckpoint<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    try await acquire(.background)
    let work = Task {
      try Task.checkCancellation()
      return try await operation()
    }
    cancelBackground = { work.cancel() }
    if waiters.contains(where: { $0.priority == .interactive }) { work.cancel() }
    do {
      let result = try await withTaskCancellationHandler {
        try await work.value
      } onCancel: {
        work.cancel()
      }
      cancelBackground = nil
      await release()
      return result
    } catch {
      cancelBackground = nil
      await release()
      throw error
    }
  }
  func release() async {
    let next = waiters.isEmpty ? nil : waiters.removeFirst()
    let previousInteractive = interactiveOccupant
    interactiveOccupant = next?.priority == .interactive
    occupied = next != nil
    if previousInteractive != interactiveOccupant {
      await observeInteractive(interactiveOccupant ? .began : .ended)
    }
    next?.continuation.resume()
  }
  private func cancel(_ id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
    waiters.remove(at: index).continuation.resume(throwing: CancellationError())
  }
}
