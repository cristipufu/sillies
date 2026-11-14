import Foundation
import Testing

@testable import SilliesCore

@Test func speechBoundaryColdStartsPreserveEveryPreviouslyAcceptedFrame() {
  for mode in SpeechBoundaryPolicy.Mode.allCases {
    var policy = SpeechBoundaryPolicy(mode: mode)
    for _ in 0..<5_000 {
      let activity = policy.observe(energy: 0.003, sampleCount: 160)
      #expect(activity == .voice)
    }
    #expect(policy.retainedNoiseFrames == 0)
  }
}

@Test func speechBoundaryQuietCalibrationDoesNotLearnEstablishedSpeechAsNoise() {
  var adaptive = SpeechBoundaryPolicy(mode: .adaptive)
  var baseline = SpeechBoundaryPolicy(mode: .baseline)
  for _ in 0..<20 { _ = adaptive.observe(energy: 0, sampleCount: 160) }
  let noiseCount = adaptive.retainedNoiseFrames
  for _ in 0..<4_000 {
    let heard = adaptive.observe(energy: 0.0018, sampleCount: 160)
    #expect(heard == .voice)
  }
  let missed = baseline.observe(energy: 0.0018, sampleCount: 160)
  #expect(missed == .quiet)
  #expect(adaptive.retainedNoiseFrames == noiseCount)
}

@Test func speechBoundaryNoiseStateAndInvalidInputsStayBounded() {
  var policy = SpeechBoundaryPolicy(mode: .adaptive)
  for _ in 0..<1_000 { _ = policy.observe(energy: 0.0001, sampleCount: 160) }
  #expect(policy.retainedNoiseFrames == SpeechBoundaryPolicy.maximumNoiseFrames)
  for energy: Float in [.nan, .infinity, -.infinity, -1] {
    let result = policy.observe(energy: energy, sampleCount: 160)
    #expect(result == .invalid)
  }
  let invalidCount = policy.observe(energy: 0, sampleCount: -1)
  #expect(invalidCount == .invalid)
  _ = policy.observe(energy: 0, sampleCount: .max)
  #expect(policy.retainedNoiseFrames == SpeechBoundaryPolicy.maximumNoiseFrames)
  policy.reset()
  #expect(policy.retainedNoiseFrames == 0)

}

@Test func speechBoundaryKeepsSourceCalibrationAcrossPausesAndResetsWithItsLifetime() {
  var policy = SpeechBoundaryPolicy(mode: .adaptive)
  for _ in 0..<20 { _ = policy.observe(energy: 0, sampleCount: 160) }
  _ = policy.observe(energy: 0.03, sampleCount: 160)
  for _ in 0..<80 {
    let activity = policy.observe(energy: 0.0018, sampleCount: 160)
    #expect(activity == .quiet)
  }
  for _ in 0..<1_000 {
    _ = policy.observe(energy: 0, sampleCount: 160)
  }
  let afterPause = policy.observe(energy: 0.0018, sampleCount: 160)
  #expect(afterPause == .quiet)
  policy.reset()
  for _ in 0..<20 { _ = policy.observe(energy: 0, sampleCount: 160) }
  let nextSource = policy.observe(energy: 0.0018, sampleCount: 160)
  #expect(nextSource == .voice)
}
