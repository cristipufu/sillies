import Darwin
import Foundation

/// Opt-in wall/CPU correlation for bounded native drag investigations, outside the app hot path.
@MainActor final class DragFrameDiagnostics {
  private static let millisecondsPerSecond = 1_000.0
  private static let nanosecondsPerMillisecond = 1_000_000.0
  private struct Sample {
    let frame: Int
    let elapsed: Double
    let cpu: Double
  }
  private var slowest: Sample?

  static func fromEnvironment() -> DragFrameDiagnostics? {
    ProcessInfo.processInfo.environment["SILLIES_DRAG_DIAGNOSTICS"] == "1"
      ? DragFrameDiagnostics() : nil
  }

  func measure(frame: Int, operation: () -> Void) {
    let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    let start = ProcessInfo.processInfo.systemUptime
    operation()
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    let cpuEnd = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    guard elapsed > (slowest?.elapsed ?? 0), cpuStart > 0, cpuEnd >= cpuStart else { return }
    slowest = .init(
      frame: frame, elapsed: elapsed,
      cpu: Double(cpuEnd - cpuStart) / Self.nanosecondsPerMillisecond)
  }

  var summary: String {
    guard let slowest else { return "No drag samples" }
    return String(
      format: "slowest frame %d: wall %.3f ms, thread CPU %.3f ms",
      slowest.frame, slowest.elapsed * Self.millisecondsPerSecond, slowest.cpu)
  }
}
