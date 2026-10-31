import Testing

@testable import SilliesSpeech

@Test func incrementalSpeechDecodesEachNewSampleOnceAndRestartsAtOverlapBoundaries() {
  var progress = SpeechIncrementalWindow()
  var request = SpeechWindowRequest(samples: [1, 2], language: .automatic)
  request.window = .init(start: 0, phase: .partial)
  let first = progress.advance(request)
  #expect(first.action == .restart && first.samples == [1, 2])
  request = SpeechWindowRequest(samples: [1, 2, 3, 4], language: .automatic)
  request.window = .init(start: 0, phase: .partial)
  let second = progress.advance(request)
  #expect(second.action == .append && second.samples == [3, 4])
  request.window = .init(start: 0, phase: .complete)
  let final = progress.advance(request)
  #expect(final.samples.isEmpty && final.phase == .complete)
  request.window = .init(start: 0.2, phase: .partial)
  let restarted = progress.advance(request)
  #expect(restarted.action == .restart)
}

@Test func incrementalSpeechStartsFreshAfterFinalizationAndStandaloneValidation() {
  var progress = SpeechIncrementalWindow()
  let validation = SpeechWindowRequest(samples: [1, 2, 3], language: .automatic)
  let first = progress.advance(validation)
  let second = progress.advance(validation)
  #expect(first.samples == [1, 2, 3])
  #expect(second.samples == [1, 2, 3])
  var request = SpeechWindowRequest(samples: [4], language: .automatic)
  request.window = .init(start: 0, phase: .partial)
  let update = progress.advance(request)
  #expect(update.samples == [4])
}

@Test func streamingCadenceProducesEarlyPartialsAndKeepsAudioBounded() throws {
  var buffer = SpeechWindowBuffer()
  buffer.cadence = .streaming
  let tick = [Float](repeating: 0.1, count: 8_960)
  var transcript = SpeechWindowTranscript()
  // Thousands of streaming ticks exercise rollover without waiting for real-time audio.
  for _ in 0..<10_000 {
    try buffer.append(tick)
    let next = buffer.next(mode: .live)
    let window = try #require(next)
    #expect(window.samples.count <= 192_000)
    let result = transcript.receive(.init(words: []), window: window)
    buffer.retire(window, through: result.retiredThrough)
    #expect(buffer.samples.count <= 192_000)
  }
}
