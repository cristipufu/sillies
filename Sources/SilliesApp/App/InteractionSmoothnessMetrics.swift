import Foundation

/// Structural frame-budget monitor for the four primary interactive hot paths.
/// Enforces that synchronous main-thread work stays well below a single 120Hz frame (8.33ms).
@MainActor
final class InteractionSmoothnessMetrics {
  enum Path: String, CaseIterable {
    case windowMove
    case windowResize
    case windowSwitch
    case companionDrag
  }

  enum Stage: String, CaseIterable {
    case targeting, surfaces, screenGeometry, surfaceConfiguration, arrangement, nativePlacement
    case behavior, interaction, clocks
  }
  private struct Frame {
    var stages: [Stage: TimeInterval] = [:]
  }

  struct Budget {
    static let standard = Self(p50Milliseconds: 0.75, p90Milliseconds: 1.5)
    // Explicit opt-in for the stress fixture moving all 12 native mascot windows.
    static let fullCrew = Self(p50Milliseconds: 2.5, p90Milliseconds: 3.0)
    let p50Milliseconds: Double
    let p90Milliseconds: Double
    let p95Milliseconds: Double = 4.0
    let maximumMilliseconds: Double = 1000.0 / 120.0
  }

  private static let millisecondsPerSecond: Double = 1000
  private static let p50Percentile: Double = 0.50
  private static let p90Percentile: Double = 0.90
  private static let p95Percentile: Double = 0.95
  private static let sampleCapacity = 4096

  private let clock: () -> TimeInterval
  var isEnabled: Bool
  private var samples: [Path: [TimeInterval]] = [:]
  private var nextSampleIndex: [Path: Int] = [:]
  private var totals: [Path: Int] = [:]
  private var maxima: [Path: TimeInterval] = [:]
  private var currentFrame: Frame?
  private var slowestFrames: [Path: Frame] = [:]

  init(
    enabled: Bool = false,
    clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  ) {
    self.isEnabled = enabled
    self.clock = clock
  }

  func reset() {
    samples.removeAll(keepingCapacity: true)
    nextSampleIndex.removeAll(keepingCapacity: true)
    totals.removeAll(keepingCapacity: true)
    maxima.removeAll(keepingCapacity: true)
    slowestFrames.removeAll(keepingCapacity: true)
  }

  func measure<T>(_ path: Path, _ operation: () -> T) -> T {
    guard isEnabled else { return operation() }
    let preceding = currentFrame
    currentFrame = Frame()
    let start = clock()
    defer {
      let duration = clock() - start
      if duration >= maxima[path, default: 0] { slowestFrames[path] = currentFrame }
      record(duration, for: path)
      currentFrame = preceding
    }
    return operation()
  }

  func measureStage<T>(_ stage: Stage, _ operation: () -> T) -> T {
    guard isEnabled, currentFrame != nil else { return operation() }
    let start = clock()
    defer {
      currentFrame?.stages[stage, default: 0] += clock() - start
    }
    return operation()
  }

  func slowestFrameMilliseconds(for path: Path, stage: Stage) -> Double {
    (slowestFrames[path]?.stages[stage] ?? 0) * Self.millisecondsPerSecond
  }

  func sampleCount(for path: Path) -> Int {
    totals[path, default: 0]
  }

  func record(_ duration: TimeInterval, for path: Path) {
    guard isEnabled else { return }
    totals[path, default: 0] += 1
    maxima[path] = max(maxima[path, default: 0], duration)
    if samples[path, default: []].count < Self.sampleCapacity {
      samples[path, default: []].append(duration)
    } else {
      let index = nextSampleIndex[path, default: 0]
      samples[path]?[index] = duration
      nextSampleIndex[path] = (index + 1) % Self.sampleCapacity
    }
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
    maxima[path, default: 0] * Self.millisecondsPerSecond
  }

  func isWithinBudget(for path: Path, budget: Budget = .standard) -> Bool {
    sampleCount(for: path) > 0
      && p50Milliseconds(for: path) <= budget.p50Milliseconds
      && p90Milliseconds(for: path) <= budget.p90Milliseconds
      && p95Milliseconds(for: path) <= budget.p95Milliseconds
      && maxMilliseconds(for: path) <= budget.maximumMilliseconds
  }

  var summary: String {
    Path.allCases.filter { sampleCount(for: $0) > 0 }.map { path in
      let timing = String(
        format: "%@: p50 %.2f, p90 %.2f, p95 %.2f, max %.2f ms (%d samples)", path.rawValue,
        p50Milliseconds(for: path), p90Milliseconds(for: path), p95Milliseconds(for: path),
        maxMilliseconds(for: path),
        sampleCount(for: path))
      let stages = Stage.allCases.compactMap { stage -> String? in
        guard let duration = slowestFrames[path]?.stages[stage] else { return nil }
        return String(format: "%@ %.2f", stage.rawValue, duration * Self.millisecondsPerSecond)
      }.joined(separator: ", ")
      return stages.isEmpty ? timing : timing + "; slowest frame stages (inclusive ms): " + stages
    }.joined(separator: "; ")
  }

  var diagnosticReport: String {
    summary
      + "; thermal state \(ProcessInfo.processInfo.thermalState.rawValue), low power \(ProcessInfo.processInfo.isLowPowerModeEnabled)"
  }

  private func percentileMilliseconds(_ percentile: Double, for path: Path) -> Double {
    guard let recorded = samples[path], !recorded.isEmpty else { return 0 }
    let sorted = recorded.sorted()
    let index = min(sorted.count - 1, Int(Double(sorted.count) * percentile))
    return sorted[index] * Self.millisecondsPerSecond
  }
}
