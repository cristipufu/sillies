import Foundation
import SilliesCore
import Testing

@testable import SilliesAudio

@Test(arguments: [
  AcousticReplayFixture.Scenario.phraseRestarts, .reverberation, .gainChange, .callbackJitter,
  .clockDrift,
])
func voiceAcousticReplayPreservesSpeakerOnlyPlayback(scenario: AcousticReplayFixture.Scenario)
  async throws
{
  try await Task.detached {
    let report = try AcousticReplayFixture(scenario: scenario, signals: .synthetic()).run()
    print(
      "ACOUSTIC \(scenario.rawValue): starts=\(report.starts), reference=\(report.checkpoint.window.referenceSamples)/\(report.checkpoint.window.samples), resets=\(report.final.delivery.referenceDiscontinuities)"
    )
    #expect(report.starts.isEmpty)
  }.value
}

@Test(arguments: [AcousticReplayFixture.Scenario.quietInterruption, .shortInterruption])
func voiceAcousticReplayPreservesQuietAndShortInterruptions(
  scenario: AcousticReplayFixture.Scenario
) async throws {
  try await Task.detached {
    let report = try AcousticReplayFixture(scenario: scenario, signals: .synthetic()).run()
    #expect(!report.starts.contains { $0 < 5 })
    #expect(report.starts.contains { $0 >= 5 && $0 < 5.6 })
  }.value
}

@Test(arguments: [AcousticReplayFixture.Scenario.missingReference, .lateReference, .clipping])
func voiceAcousticReplayExplainsDegradedInputWithoutHidingIt(
  scenario: AcousticReplayFixture.Scenario
) async throws {
  try await Task.detached {
    let report = try AcousticReplayFixture(scenario: scenario, signals: .synthetic()).run()
    print(
      "ACOUSTIC \(scenario.rawValue): starts=\(report.starts), clipped=\(report.checkpoint.window.clippedSamples), reference=\(report.checkpoint.window.referenceSamples)/\(report.checkpoint.window.samples), stale=\(report.final.delivery.staleReferenceFrames)"
    )
    switch scenario {
    case .missingReference:
      #expect(report.checkpoint.window.referenceSamples < report.checkpoint.window.samples / 2)
    case .lateReference: #expect(report.final.delivery.staleReferenceFrames > 0)
    case .clipping: #expect(report.checkpoint.window.clippedSamples > 0)
    default: Issue.record("Unexpected degradation scenario")
    }
  }.value
}

/// Explicit generated voice fixtures only. Reports observations rather than treating impaired inputs as acceptance passes.
@Test(
  .enabled(if: ProcessInfo.processInfo.environment["SILLIES_ACOUSTIC_FAR_FIXTURE"] != nil),
  arguments: AcousticReplayFixture.Scenario.allCases)
func voiceAcousticPrerecordedInvestigation(scenario: AcousticReplayFixture.Scenario) async throws {
  let far = try #require(ProcessInfo.processInfo.environment["SILLIES_ACOUSTIC_FAR_FIXTURE"])
  let near = try #require(ProcessInfo.processInfo.environment["SILLIES_ACOUSTIC_NEAR_FIXTURE"])
  try await Task.detached {
    let signals = try AcousticReplayFixture.Signals.prerecorded(far: far, near: near)
    let report = try AcousticReplayFixture(scenario: scenario, signals: signals).run()
    let value = report.checkpoint
    if let onset = report.boundaries.first(where: { $0.boundary == .onset }) {
      print(
        "SPOKEN ONSET \(scenario.rawValue): referenceDB=\(onset.window.referenceDecibels); microphoneDB=\(onset.window.microphoneDecibels); cleanedDB=\(onset.window.cleanedDecibels); ERLE=\(String(describing: onset.echo.reductionDecibels)); delayMS=\(String(describing: onset.echo.delayMilliseconds))"
      )
    }
    print(
      "SPOKEN ACOUSTIC \(scenario.rawValue): starts=\(report.starts); coverage=\(value.window.referenceSamples)/\(value.window.samples); clipped=\(value.window.clippedSamples); cleanedDB=\(value.window.cleanedDecibels); ERLE=\(String(describing: value.echo.reductionDecibels)); delayMS=\(String(describing: value.echo.delayMilliseconds)); stale=\(report.final.delivery.staleReferenceFrames); resets=\(report.final.delivery.referenceDiscontinuities)"
    )
    #expect(value.window.cleanedDecibels.isFinite)
  }.value
}
