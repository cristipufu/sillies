import Foundation
import SilliesInference
import XCTest

@testable import SilliesSpeech

final class SpeechSchedulerTests: XCTestCase, @unchecked Sendable {
  func testEveryOutcomeReleasesSpeechBeforeReturning() async {
    for outcome in AdmissionEngine.Outcome.allCases {
      let activity = InferenceActivity()
      let scheduler = SpeechInferenceScheduler(
        engine: AdmissionEngine(outcome: outcome), activity: activity)
      do {
        _ = try await scheduler.transcribe(.init(samples: [1], language: .automatic))
        XCTAssertEqual(outcome, .success)
      } catch is CancellationError {
        XCTAssertEqual(outcome, .cancelled)
      } catch is SpeechError {
        XCTAssertEqual(outcome, .failure)
      } catch { XCTFail("Unexpected error: \(error)") }
      let speech = UUID()
      let admitted = await activity.claimSynthesis(speech, cancel: {})
      XCTAssertTrue(admitted, "A completed recognition job must release inference admission")
      await activity.releaseSynthesis(speech)
    }
  }

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

  func testInteractiveInferenceRunsWithUserInitiatedPriority() async throws {
    let engine = ObservedEngine()
    let scheduler = SpeechInferenceScheduler(engine: engine)
    _ = try await scheduler.transcribe(
      .init(
        samples: [1], language: .automatic,
        context: .init(priority: .interactive)))
    let priority = await engine.observedPriority
    XCTAssertGreaterThanOrEqual(priority, .userInitiated)
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

private struct AdmissionEngine: SpeechWindowEngine {
  enum Outcome: CaseIterable { case success, failure, cancelled }
  let outcome: Outcome

  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    switch outcome {
    case .success: return .init(words: [])
    case .failure: throw SpeechError.unavailable("Fixture recognition failure")
    case .cancelled: throw CancellationError()
    }
  }
}

private actor ObservedEngine: SpeechWindowEngine {
  private(set) var maximumConcurrent = 0
  private(set) var observedMainThread = false
  private(set) var calls = 0
  private(set) var observedPriority = TaskPriority.background
  private var active = 0

  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    observedMainThread = observedMainThread || Thread.isMainThread
    observedPriority = Task.currentPriority
    calls += 1
    active += 1
    maximumConcurrent = max(maximumConcurrent, active)
    defer { active -= 1 }
    try await Task.sleep(for: .milliseconds(30))
    return .init(words: [])
  }
}
