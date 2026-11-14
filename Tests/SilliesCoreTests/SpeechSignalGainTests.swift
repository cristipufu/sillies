import Testing

@testable import SilliesCore

@Test func speechSignalGainPreservesSilenceAndBoundsAmplificationWithoutNewClipping() throws {
  for peak: Float in [0, 0.0001, 0.01, 0.03, 0.04, 0.08, 0.15, 0.3, 0.6, 1, 2] {
    var policy = SpeechSignalGain()
    let observed = policy.observe(peak: peak)
    let gain = try #require(observed)
    #expect(gain >= 1 && gain <= 2)
    #expect(peak * gain <= max(0.125, peak))
    if peak == 0 { #expect(gain == 1) }
  }
}

@Test func speechSignalGainStaysStableThroughQuietGapsAndResetsWithItsSource() throws {
  var policy = SpeechSignalGain()
  let quietObservation = policy.observe(peak: 0.01)
  let quiet = try #require(quietObservation)
  #expect(quiet == 2)
  let louderObservation = policy.observe(peak: 0.08)
  let louder = try #require(louderObservation)
  #expect(louder == 1)
  for _ in 0..<1_000 {
    let afterGap = policy.observe(peak: 0)
    #expect(afterGap == louder)
  }
  policy.reset()
  let freshObservation = policy.observe(peak: 0.01)
  let fresh = try #require(freshObservation)
  #expect(fresh == quiet)
}

@Test func speechSignalGainRejectsInvalidPeaksWithoutChangingSourceState() {
  var policy = SpeechSignalGain()
  for peak: Float in [-1, .nan, .infinity, -.infinity] {
    let gain = policy.observe(peak: peak)
    #expect(gain == nil)
  }
  let valid = policy.observe(peak: 0.01)
  #expect(valid == 2)
}
