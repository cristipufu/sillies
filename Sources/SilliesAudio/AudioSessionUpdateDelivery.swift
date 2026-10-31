import Foundation
import Synchronization

/// Coalesces progress between lifecycle events and schedules at most one UI delivery.
package final class AudioSessionUpdateDelivery: Sendable {
  package typealias Update = AudioCaptureUpdate
  package typealias Schedule = @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
  package struct Metrics: Sendable {
    package var pendingUpdates = 0
    package var peakPendingUpdates = 0
    package var scheduledDeliveries = 0
  }
  private struct State {
    var pending: [Update] = []
    var scheduled = false
    var stopped = false
    var metrics = Metrics()
  }
  private let state = Mutex(State())
  private let receive: @MainActor @Sendable (Update) -> Void
  private let schedule: Schedule

  package init(
    schedule: @escaping Schedule,
    receive: @escaping @MainActor @Sendable (Update) -> Void
  ) {
    self.schedule = schedule
    self.receive = receive
  }

  package var metrics: Metrics { state.withLock { $0.metrics } }

  package func enqueue(_ update: Update) {
    let needsDelivery = state.withLock { state in
      guard !state.stopped else { return false }
      if case .transcript = update, case .transcript = state.pending.last {
        state.pending[state.pending.count - 1] = update
      } else {
        state.pending.append(update)
      }
      state.metrics.pendingUpdates = state.pending.count
      state.metrics.peakPendingUpdates = max(state.metrics.peakPendingUpdates, state.pending.count)
      guard !state.scheduled else { return false }
      state.scheduled = true
      state.metrics.scheduledDeliveries += 1
      return true
    }
    if needsDelivery { schedule { [weak self] in self?.drain() } }
  }

  @MainActor private func drain() {
    let updates = state.withLock { state in
      let updates = state.pending
      state.pending.removeAll(keepingCapacity: true)
      state.scheduled = false
      state.metrics.pendingUpdates = 0
      return updates
    }
    for update in updates {
      guard !state.withLock({ $0.stopped }) else { return }
      receive(update)
    }
  }

  package func stop() {
    state.withLock {
      $0.stopped = true
      $0.pending.removeAll()
      $0.metrics.pendingUpdates = 0
    }
  }
}
