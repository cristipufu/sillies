import Foundation
import Synchronization

/// Native property changes coalesce before entering the capture worker. Audio callbacks never use it.
final class CoreAudioChangeDelivery: Sendable {
  struct Signal: Sendable {
    let change: CoreAudioCaptureChange
    let ticket: UUID
  }
  private struct State {
    var pending: Signal?
    var scheduled = false
  }
  private let state = Mutex(State())
  private let queue: DispatchQueue
  private let receive: @Sendable (Signal) -> Void
  init(queue: DispatchQueue, receive: @escaping @Sendable (Signal) -> Void) {
    self.queue = queue
    self.receive = receive
  }
  func send(_ signal: Signal) {
    let schedule = state.withLock { state in
      let change: CoreAudioCaptureChange =
        state.pending?.change == .configuration ? .configuration : signal.change
      state.pending = .init(change: change, ticket: signal.ticket)
      guard !state.scheduled else { return false }
      state.scheduled = true
      return true
    }
    if schedule { queue.async { [self] in drain() } }
  }
  private func drain() {
    let signal = state.withLock { state in
      defer {
        state.pending = nil
        state.scheduled = false
      }
      return state.pending
    }
    if let signal { receive(signal) }
  }
}
