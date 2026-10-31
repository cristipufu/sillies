import Foundation

/// Process termination may arrive before or after an async waiter registers.
final class WorkerExitSignal: @unchecked Sendable {
  private let lock = NSLock()
  private var completed = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func waitForCompletion() async {
    await withCheckedContinuation { continuation in
      let alreadyComplete = lock.withLock {
        if completed { return true }
        waiters.append(continuation)
        return false
      }
      if alreadyComplete { continuation.resume() }
    }
  }

  func complete() {
    let pending = lock.withLock {
      completed = true
      let pending = waiters
      waiters.removeAll()
      return pending
    }
    for waiter in pending { waiter.resume() }
  }
}
