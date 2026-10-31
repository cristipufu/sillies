import Foundation
import Testing

@testable import SilliesApp

@Test @MainActor func smoothnessDiagnosticsDescribeTheSlowestFrameAndKeepPathsSeparate() {
  var time = 0.0
  let metrics = InteractionSmoothnessMetrics(enabled: true, clock: { time })
  metrics.measure(.windowMove) {
    metrics.measureStage(.nativePlacement) { time += 0.010 }
    metrics.measureStage(.interaction) { time += 0.002 }
  }
  metrics.measure(.windowMove) {
    metrics.measureStage(.nativePlacement) { time += 0.001 }
  }
  metrics.measure(.windowResize) {
    metrics.measureStage(.screenGeometry) { time += 0.003 }
  }
  #expect(
    abs(metrics.slowestFrameMilliseconds(for: .windowMove, stage: .nativePlacement) - 10) < 0.0001)
  #expect(metrics.slowestFrameMilliseconds(for: .windowMove, stage: .screenGeometry) == 0)
  #expect(
    abs(metrics.slowestFrameMilliseconds(for: .windowResize, stage: .screenGeometry) - 3) < 0.0001)
  #expect(!metrics.isWithinBudget(for: .windowMove))
  #expect(metrics.diagnosticReport.contains("nativePlacement 10.00"))
  metrics.reset()
  #expect(metrics.slowestFrameMilliseconds(for: .windowMove, stage: .nativePlacement) == 0)
  #expect(metrics.sampleCount(for: .windowMove) == 0)
}
