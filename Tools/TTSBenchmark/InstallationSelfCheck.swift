import Darwin
import Foundation
import SilliesTTS
import Synchronization

enum InstallationSelfCheck {
  static func run() async throws {
    for argument in ["0", "-1", "nan", "inf", "86401", "not-a-duration"] {
      do {
        _ = try BenchmarkInstallation.timeout(argument)
        throw Failure.invalidTimeoutAccepted
      } catch TTSError.unavailable {}
    }
    guard try BenchmarkInstallation.timeout(nil) == BenchmarkInstallation.defaultTimeoutSeconds,
      try BenchmarkInstallation.timeout("900") == 900
    else { throw Failure.validTimeoutRejected }
    try await BenchmarkInstallation.perform(timeout: 1) {}
    try await checkInterruption(.deadline)
    try await checkInterruption(.signal(SIGINT))
    try await checkInterruption(.signal(SIGTERM))
    try await checkParentCancellation()
    print("Installation signals, deadline and cancellation cleanup: passed")
  }

  private static func checkInterruption(_ expected: BenchmarkInstallation.Interruption) async throws
  {
    let cleaned = Mutex(false)
    let timeout: TimeInterval = expected == .deadline ? 0.1 : 2
    do {
      try await BenchmarkInstallation.perform(timeout: timeout) {
        do {
          if case .signal(let number) = expected, kill(getpid(), number) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
          }
          try await Task.sleep(for: .seconds(5))
        } catch {
          await Task.yield()
          cleaned.withLock { $0 = true }
          throw error
        }
      }
      throw Failure.interruptionMissing
    } catch let observed as BenchmarkInstallation.Interruption {
      guard observed == expected, cleaned.withLock({ $0 }) else {
        throw Failure.cleanupNotJoined
      }
    }
  }

  private static func checkParentCancellation() async throws {
    let (events, input) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
    defer { input.finish() }
    let cleaned = Mutex(false)
    let task = Task {
      try await BenchmarkInstallation.perform(timeout: 2) {
        input.yield()
        do { try await Task.sleep(for: .seconds(5)) } catch {
          await Task.yield()
          cleaned.withLock { $0 = true }
          throw error
        }
      }
    }
    for await _ in events { break }
    task.cancel()
    do {
      try await task.value
      throw Failure.interruptionMissing
    } catch is CancellationError {
      guard cleaned.withLock({ $0 }) else { throw Failure.cleanupNotJoined }
    }
  }

  private enum Failure: Error {
    case invalidTimeoutAccepted, validTimeoutRejected, interruptionMissing, cleanupNotJoined
  }
}
