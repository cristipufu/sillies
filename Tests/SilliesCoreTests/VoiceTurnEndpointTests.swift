import SilliesCore
import Testing

@Test func voiceTurnEndpointWaitsForSpeechAndToleratesNaturalPauses() {
  var endpoint = VoiceTurnEndpoint()
  for _ in 0..<1000 { #expect(endpoint.consume(isSpeech: false, duration: 0.01) == nil) }
  var starts = 0
  for _ in 0..<40 { if endpoint.consume(isSpeech: true, duration: 0.01) == .began { starts += 1 } }
  #expect(starts == 1)
  for _ in 0..<50 { #expect(endpoint.consume(isSpeech: false, duration: 0.01) == nil) }
  for _ in 0..<30 { #expect(endpoint.consume(isSpeech: true, duration: 0.01) == nil) }
  var ends = 0
  for _ in 0..<100 { if endpoint.consume(isSpeech: false, duration: 0.01) == .ended { ends += 1 } }
  #expect(ends == 1)
  for _ in 0..<100 { #expect(endpoint.consume(isSpeech: false, duration: 0.01) == nil) }
}

@Test func voiceTurnEndpointIgnoresClicksAndInvalidDurations() {
  var endpoint = VoiceTurnEndpoint()
  for duration: Double in [.nan, .infinity, -1, 0, 100] {
    #expect(endpoint.consume(isSpeech: true, duration: duration) == nil)
  }
  for _ in 0..<100 {
    #expect(endpoint.consume(isSpeech: true, duration: 0.01) == nil)
    for _ in 0..<10 { #expect(endpoint.consume(isSpeech: false, duration: 0.01) == nil) }
  }
}
