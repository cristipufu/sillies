import Testing

@testable import SilliesCore

@Test func speechSignalGainPreservesSilenceAndBoundsAmplificationWithoutNewClipping() throws {
  for peak: Float in [0, 0.0001, 0.01, 0.03, 0.04, 0.08, 0.15, 0.3, 0.6, 1, 2] {
    var policy = SpeechSignalGain()
    let observed = policy.observe(peak: peak, rootMeanSquare: 0)
    let gain = try #require(observed)
    #expect(gain >= 1 && gain <= 2)
    #expect(peak * gain <= max(0.125, peak))
    if peak == 0 { #expect(gain == 1) }
  }
}

@Test func speechSignalGainStaysStableThroughQuietGapsAndResetsWithItsSource() throws {
  var policy = SpeechSignalGain()
  let quietObservation = policy.observe(peak: 0.01, rootMeanSquare: 0)
  let quiet = try #require(quietObservation)
  #expect(quiet == 2)
  let louderObservation = policy.observe(peak: 0.08, rootMeanSquare: 0)
  let louder = try #require(louderObservation)
  #expect(louder == 1)
  for _ in 0..<1_000 {
    let afterGap = policy.observe(peak: 0, rootMeanSquare: 0)
    #expect(afterGap == louder)
  }
  policy.reset()
  let freshObservation = policy.observe(peak: 0.01, rootMeanSquare: 0)
  let fresh = try #require(freshObservation)
  #expect(fresh == quiet)
}

@Test func speechSignalGainRejectsInvalidPeaksWithoutChangingSourceState() {
  var policy = SpeechSignalGain()
  for peak: Float in [-1, .nan, .infinity, -.infinity] {
    let gain = policy.observe(peak: peak, rootMeanSquare: 0)
    #expect(gain == nil)
  }
  let valid = policy.observe(peak: 0.01, rootMeanSquare: 0)
  #expect(valid == 2)
}

@Test func speechSignalGainForDetectionPreservesItsBoundAfterResetWithoutChangingDecoderDefaults() {
  var detection = SpeechSignalGain(purpose: .detection)
  var decoding = SpeechSignalGain()
  #expect(detection.observe(peak: 0.001, rootMeanSquare: 0) == 16)
  #expect(decoding.observe(peak: 0.001, rootMeanSquare: 0) == 2)
  #expect(detection.observe(peak: 0.8, rootMeanSquare: 0) == 1)
  detection.reset()
  #expect(detection.observe(peak: 0.001, rootMeanSquare: 0) == 16)
  for peak: Float in [0, 0.001, 0.01, 0.04, 0.08, 0.6, 1] {
    var policy = SpeechSignalGain(purpose: .detection)
    let gain = policy.observe(peak: peak, rootMeanSquare: 0)
    #expect(gain.map { $0 >= 1 && $0 <= 16 && peak * $0 <= max(0.125, peak) } == true)
  }
}

@Test func speechSignalGainForDetectionDoesNotBoostAudibleNoiseAndStillLiftsQuietSpeech() {
  var analysis = SpeechSignalGain(purpose: .detection)
  let noise = analysis.observe(peak: 0.059, rootMeanSquare: 0.014)
  #expect(noise == 1)
  analysis.reset()
  let speech = analysis.observe(peak: 0.01, rootMeanSquare: 0.0012)
  #expect(speech == 8)
  let afterQuietGap = analysis.observe(peak: 0.001, rootMeanSquare: 0.0001)
  #expect(afterQuietGap == speech)
  analysis.reset()
  for energy: Float in [-1, .nan, .infinity, 0.2] {
    let invalid = analysis.observe(peak: 0.1, rootMeanSquare: energy)
    #expect(invalid == nil)
  }
  let afterInvalid = analysis.observe(peak: 0.01, rootMeanSquare: 0.0012)
  #expect(afterInvalid == speech)
}
