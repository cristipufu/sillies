import Foundation
import Synchronization

/// Cancellation stays with the capture owner; scheduling can be driven without elapsed time in tests.
struct CaptureDeadline: Sendable {
  private let cancelWork: @Sendable () -> Void
  init(cancel: @escaping @Sendable () -> Void) { cancelWork = cancel }
  func cancel() { cancelWork() }

  static func queued(
    on queue: DispatchQueue, after delay: TimeInterval,
    perform action: @escaping @Sendable () -> Void
  ) -> Self {
    let pending = Mutex<DispatchWorkItem?>(nil)
    pending.withLock { work in
      let scheduled = DispatchWorkItem(block: action)
      work = scheduled
      queue.asyncAfter(deadline: .now() + delay, execute: scheduled)
    }
    return Self {
      pending.withLock { work in
        work?.cancel()
        work = nil
      }
    }
  }
}
