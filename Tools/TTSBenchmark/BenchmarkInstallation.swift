import Foundation
import SilliesModelStore
import SilliesTTS

enum BenchmarkInstallation {
  static let defaultTimeoutSeconds: TimeInterval = 30 * 60
  private static let maximumTimeoutSeconds: TimeInterval = 24 * 60 * 60

  enum Interruption: Error, LocalizedError, Equatable {
    case signal(Int32)
    case deadline

    var errorDescription: String? {
      switch self {
      case .signal(let number): "Installation interrupted by signal \(number)."
      case .deadline: "The installation deadline expired."
      }
    }
  }

  static func timeout(_ argument: String?) throws -> TimeInterval {
    guard let argument else { return defaultTimeoutSeconds }
    guard let value = TimeInterval(argument), value.isFinite, value > 0,
      value <= maximumTimeoutSeconds
    else {
      throw TTSError.unavailable(
        "Installation timeout must be greater than 0 and at most 86400 seconds.")
    }
    return value
  }

  static func run(
    manifest: TTSModelManifest, store: ModelStore, timeout: TimeInterval
  ) async throws {
    let progress = InstallationProgress()
    fputs(
      "Installing \(manifest.model.name): \(manifest.downloadBytes) bytes; setup deadline \(timeout)s.\n",
      stderr)
    do {
      try await perform(timeout: timeout) {
        if try await store.isInstalled(manifest) {
          fputs("Verifying existing installation…\n", stderr)
          let lease = try await store.acquire(manifest)
          await lease.close()
        } else {
          try await store.install(manifest, progress: progress.receive)
        }
      }
    } catch {
      fputs(
        "Installation stopped after cleanup. Rerun the same command to reuse saved progress.\n",
        stderr)
      throw error
    }
    print("Verified installation: \(manifest.model.name)")
  }

  /// Await cancellation cleanup so ModelDownloadClient can persist URLSession's resume data.
  static func perform(
    timeout: TimeInterval, operation: @escaping @Sendable () async throws -> Void
  ) async throws {
    try Task.checkCancellation()
    let (events, input) = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingOldest(1))
    let signals = try BenchmarkInterrupts { input.yield($0) }
    defer {
      signals.stop()
      input.finish()
    }
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask(operation: operation)
      group.addTask {
        try await Task.sleep(for: .seconds(timeout))
        throw Interruption.deadline
      }
      group.addTask {
        for await number in events { throw Interruption.signal(number) }
        throw CancellationError()
      }
      defer { group.cancelAll() }
      do { try await group.next() } catch let reason as Interruption {
        fputs("\(reason.localizedDescription) Cancelling and saving resumable progress…\n", stderr)
        throw reason
      }
    }
  }
}
