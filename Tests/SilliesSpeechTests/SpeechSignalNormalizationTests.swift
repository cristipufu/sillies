import Testing

@testable import SilliesSpeech

@Test func speechSignalNormalizationValidatesBeforeChangingItsSourceLevel() throws {
  var normalization = SpeechSignalNormalization()
  for invalid: Float in [.nan, .infinity, -.infinity] {
    #expect(throws: SpeechError.self) { try normalization.prepare([0.9, invalid]) }
  }
  let quiet = try normalization.prepare([0, -0.01, 0.01])
  #expect(quiet.gain == 2)
  #expect(quiet.apply(to: [0, -0.01, 0.01]) == [0, -0.02, 0.02])
  let louder = try normalization.prepare([0.8])
  #expect(louder.gain == 1)
  normalization.reset()
  let fresh = try normalization.prepare([0.01])
  #expect(fresh.gain == quiet.gain)
}

@Test func speechSignalGainChangesReplayTheRetainedPrefixAndStableGainOnlyAppends() throws {
  var normalization = SpeechSignalNormalization()
  var cursor = SpeechIncrementalWindow()
  func request(_ samples: [Float]) -> SpeechWindowRequest {
    var request = SpeechWindowRequest(samples: samples, language: .automatic)
    request.window = .init(start: 0, phase: .partial)
    return request
  }
  let first = request([0.01])
  let firstAdjustment = try normalization.prepare(first.samples)
  _ = try cursor.advance(first, inputGain: firstAdjustment.gain)
  let louder = request([0.01, 0.4])
  let adjustment = try normalization.prepare(louder.samples)
  let replay = try cursor.advance(louder, inputGain: adjustment.gain)
  #expect(replay.action == .restart)
  #expect(adjustment.apply(to: replay.samples) == [0.01, 0.4])
  let continued = request([0.01, 0.4, 0.1])
  let stable = try normalization.prepare(continued.samples)
  let appended = try cursor.advance(continued, inputGain: stable.gain)
  #expect(appended.action == .append && appended.samples == [0.1])
  cursor.reset()
  let reset = try cursor.advance(continued, inputGain: stable.gain)
  #expect(reset.action == .restart && reset.samples == continued.samples)
}
