import Foundation
import SilliesModelStore
import Synchronization

/// Throttle byte updates, but always show phase changes and completion in redirected logs.
final class InstallationProgress: Sendable {
  private struct State {
    var phase: ModelInstallationProgress.Phase?
    var lastPublication: TimeInterval = 0
  }
  private static let publicationInterval: TimeInterval = 2
  private static let bytesPerMegabyte: Double = 1_000_000
  private let state = Mutex(State())
  private let started = ProcessInfo.processInfo.systemUptime

  func receive(_ progress: ModelInstallationProgress) {
    let now = ProcessInfo.processInfo.systemUptime
    state.withLock { state in
      guard
        state.phase != progress.phase || now - state.lastPublication >= Self.publicationInterval
          || progress.completedBytes == progress.totalBytes
      else { return }
      state.phase = progress.phase
      state.lastPublication = now
      let phase = progress.phase == .downloading ? "Downloading" : "Verifying"
      let completed = Double(progress.completedBytes) / Self.bytesPerMegabyte
      let total = Double(progress.totalBytes) / Self.bytesPerMegabyte
      let percentage = progress.totalBytes > 0 ? completed / total * 100 : 0
      let line = String(
        format: "%@ %.1f%% — %.1f / %.1f MB; elapsed %.1fs\n", phase, percentage,
        completed, total, now - started)
      fputs(line, stderr)
    }
  }
}
