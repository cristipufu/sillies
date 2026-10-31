import Foundation

/// Handles cancellation arriving before an inference task has been installed.
package final class InferenceCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var cancellation: (@Sendable () -> Void)?
  private var cancelled = false
  package init() {}
  package func install(_ action: @escaping @Sendable () -> Void) {
    let run = lock.withLock {
      cancellation = action
      return cancelled
    }
    if run { action() }
  }
  package func cancel() {
    let action = lock.withLock {
      cancelled = true
      return cancellation
    }
    action?()
  }
}
