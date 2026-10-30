import Foundation

/// Opt-in local diagnostics. Normal sessions do not sample clocks or store per-event measurements.
@MainActor
final class DragResponseMetrics {
  enum Stage: String, CaseIterable {
    case movement, hitTest, releaseHitTest, targeting, highlight, wheel
  }
  var isEnabled: Bool
  private var maxima: [Stage: TimeInterval] = [:]

  init(enabled: Bool) { self.isEnabled = enabled }

  func measure<T>(_ stage: Stage, _ operation: () -> T) -> T {
    guard isEnabled else { return operation() }
    let start = ProcessInfo.processInfo.systemUptime
    defer {
      maxima[stage] = max(maxima[stage, default: 0], ProcessInfo.processInfo.systemUptime - start)
    }
    return operation()
  }

  var summary: String {
    Stage.allCases.map { String(format: "%@: %.2f ms", $0.rawValue, maxima[$0, default: 0] * 1000) }
      .joined(separator: ", ")
  }
}
