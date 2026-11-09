import SilliesCore
import Testing

@Test func voiceAcousticWindowRetainsOnlyRecentScalarEvidence() {
  var window = VoiceAcousticWindow()
  for _ in 0..<200 {
    window.append(
      .init(
        referenceSamples: 0, clippedSamples: 160,
        power: .init(reference: 0, microphone: 1, cleaned: 1)))
  }
  for _ in 0..<100 {
    window.append(
      .init(
        referenceSamples: 160, clippedSamples: 0,
        power: .init(reference: 0.1, microphone: 0.01, cleaned: 0.000_01)))
  }
  let result = window.snapshot
  #expect(result.samples == 16_000 && result.referenceSamples == 16_000)
  #expect(result.clippedSamples == 0)
  #expect(abs(result.referenceDecibels + 10) < 0.001)
  #expect(abs(result.microphoneDecibels + 20) < 0.001)
  #expect(abs(result.cleanedDecibels + 50) < 0.001)
}

@Test func voiceAcousticWindowBoundsMalformedMeasurements() {
  var window = VoiceAcousticWindow()
  window.append(
    .init(
      referenceSamples: Int.max, clippedSamples: Int.max,
      power: .init(reference: .nan, microphone: .infinity, cleaned: -1)))
  let result = window.snapshot
  #expect(result.samples == 160 && result.referenceSamples == 160 && result.clippedSamples == 160)
  #expect(
    result.referenceDecibels == -120 && result.microphoneDecibels == -120
      && result.cleanedDecibels == -120)
}
