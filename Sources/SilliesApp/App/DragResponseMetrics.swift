import Foundation

/// Opt-in local diagnostics. Normal sessions do not sample clocks or store per-event measurements.
@MainActor
final class DragResponseMetrics {
  enum Stage: String, CaseIterable {
    case movement, hitTest, releaseHitTest, targeting, highlight, wheel
  }
  private let enabled: Bool
  private var maxima: [Stage: TimeInterval] = [:]

  init(enabled: Bool) { self.enabled = enabled }

  func measure<T>(_ stage: Stage, _ operation: () -> T) -> T {
    guard enabled else { return operation() }
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

/// Structural frame-budget monitor for the four primary interactive hot paths.
/// Enforces that synchronous main-thread work stays well below a single 120Hz frame (8.33ms).
@MainActor
final class InteractionSmoothnessMetrics {
  enum Path: String, CaseIterable {
    case windowMove
    case windowResize
    case windowSwitch
    case companionDrag

    var p50BudgetMilliseconds: Double {
      0.75
    }

    var p90BudgetMilliseconds: Double {
      1.5
    }

    var p95BudgetMilliseconds: Double {
      4.0
    }
  }

  private static let millisecondsPerSecond: Double = 1000
  private static let p50Percentile: Double = 0.50
  private static let p90Percentile: Double = 0.90
  private static let p95Percentile: Double = 0.95

  var isEnabled: Bool
  private var samples: [Path: [TimeInterval]] = [:]

  init(enabled: Bool = false) {
    self.isEnabled = enabled
  }

  func reset() {
    samples.removeAll(keepingCapacity: true)
  }

  func measure<T>(_ path: Path, _ operation: () -> T) -> T {
    guard isEnabled else { return operation() }
    let start = ProcessInfo.processInfo.systemUptime
    defer {
      samples[path, default: []].append(ProcessInfo.processInfo.systemUptime - start)
    }
    return operation()
  }

  func sampleCount(for path: Path) -> Int {
    samples[path]?.count ?? 0
  }

  func p50Milliseconds(for path: Path) -> Double {
    percentileMilliseconds(Self.p50Percentile, for: path)
  }

  func p90Milliseconds(for path: Path) -> Double {
    percentileMilliseconds(Self.p90Percentile, for: path)
  }

  func p95Milliseconds(for path: Path) -> Double {
    percentileMilliseconds(Self.p95Percentile, for: path)
  }

  func maxMilliseconds(for path: Path) -> Double {
    (samples[path]?.max() ?? 0) * Self.millisecondsPerSecond
  }

  func isWithinBudget(for path: Path) -> Bool {
    p50Milliseconds(for: path) <= path.p50BudgetMilliseconds
      && p90Milliseconds(for: path) <= path.p90BudgetMilliseconds
      && p95Milliseconds(for: path) <= path.p95BudgetMilliseconds
  }

  private func percentileMilliseconds(_ percentile: Double, for path: Path) -> Double {
    guard let recorded = samples[path], !recorded.isEmpty else { return 0 }
    let sorted = recorded.sorted()
    let index = min(sorted.count - 1, Int(Double(sorted.count) * percentile))
    return sorted[index] * Self.millisecondsPerSecond
  }
}
