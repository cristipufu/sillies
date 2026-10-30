import Foundation
import XCTest

@testable import SilliesSpeech

final class SpeechSchedulerTests: XCTestCase, @unchecked Sendable {
  func testTwoSourcesShareWeightsWithoutOverlappingPredictions() async throws {
    let engine = ObservedEngine()
    let scheduler = SpeechInferenceScheduler(engine: engine)
    async let microphone = scheduler.transcribe(.init(samples: [1], language: .automatic))
    async let application = scheduler.transcribe(.init(samples: [2], language: .automatic))
    _ = try await (microphone, application)
    let maximum = await engine.maximumConcurrent
    XCTAssertEqual(maximum, 1)
    let onMainThread = await engine.observedMainThread
    XCTAssertFalse(onMainThread)
  }

  func testCancelledQueuedWorkDoesNotReachEngine() async throws {
    let engine = ObservedEngine()
    let scheduler = SpeechInferenceScheduler(engine: engine)
    let first = Task { try await scheduler.transcribe(.init(samples: [1], language: .automatic)) }
    while await engine.calls == 0 { await Task.yield() }
    let cancelled = Task {
      try await scheduler.transcribe(.init(samples: [2], language: .automatic))
    }
    cancelled.cancel()
    do {
      _ = try await cancelled.value
      XCTFail("Cancelled work succeeded")
    } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    _ = try await first.value
    let calls = await engine.calls
    XCTAssertEqual(calls, 1)
  }
}

private actor ObservedEngine: SpeechWindowEngine {
  private(set) var maximumConcurrent = 0
  private(set) var observedMainThread = false
  private(set) var calls = 0
  private var active = 0

  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    observedMainThread = observedMainThread || Thread.isMainThread
    calls += 1
    active += 1
    maximumConcurrent = max(maximumConcurrent, active)
    defer { active -= 1 }
    try await Task.sleep(for: .milliseconds(30))
    return .init(words: [])
  }
}
