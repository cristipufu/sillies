import Testing

@testable import SilliesSpeech

@Test func incrementalSpeechDecodesEachNewSampleOnceAndRestartsAtOverlapBoundaries() throws {
  var progress = SpeechIncrementalWindow()
  var request = SpeechWindowRequest(samples: [1, 2], language: .automatic)
  request.window = .init(start: 0, phase: .partial)
  let first = try progress.advance(request)
  #expect(first.action == .restart && first.samples == [1, 2])
  request = SpeechWindowRequest(samples: [1, 2, 3, 4], language: .automatic)
  request.window = .init(start: 0, phase: .partial)
  let second = try progress.advance(request)
  #expect(second.action == .append && second.samples == [3, 4])
  request.window = .init(start: 0, phase: .complete)
  let final = try progress.advance(request)
  #expect(final.samples.isEmpty && final.phase == .complete)
  request.window = .init(start: 0.2, phase: .partial)
  let restarted = try progress.advance(request)
  #expect(restarted.action == .restart)
}

@Test func incrementalSpeechStartsFreshAfterFinalizationAndStandaloneValidation() throws {
  var progress = SpeechIncrementalWindow()
  let validation = SpeechWindowRequest(samples: [1, 2, 3], language: .automatic)
  let first = try progress.advance(validation)
  let second = try progress.advance(validation)
  #expect(first.samples == [1, 2, 3])
  #expect(second.samples == [1, 2, 3])
  var request = SpeechWindowRequest(samples: [4], language: .automatic)
  request.window = .init(start: 0, phase: .partial)
  let update = try progress.advance(request)
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

@Test func incrementalSpeechCarriesNativeStateAcrossOverlappingBoundariesWithoutRepeatingAudio()
  throws
{
  var progress = SpeechIncrementalWindow()
  let samples = [Float](repeating: 0.1, count: 12 * 16_000)
  var first = SpeechWindowRequest(samples: samples, language: .automatic)
  first.window = .init(start: 0, phase: .boundary)
  _ = try progress.advance(first)
  var second = SpeechWindowRequest(samples: Array(samples.prefix(8 * 16_000)), language: .automatic)
  second.window = .init(start: 6, phase: .complete)
  let continued = try progress.advance(second)
  #expect(continued.action == .append)
  #expect(continued.samples.count == 2 * 16_000)
  #expect(continued.windowOffset == 6)
  let newUtterance = try progress.advance(first)
  #expect(newUtterance.action == .restart && newUtterance.windowOffset == 0)
}

@Test func incrementalSpeechBoundsNativeHistoryDuringContinuousInput() throws {
  var progress = SpeechIncrementalWindow()
  var restarts = 0
  let samples = [Float](repeating: 0.1, count: 12 * 16_000)
  for start in stride(from: 0, through: 70, by: 10) {
    var request = SpeechWindowRequest(samples: samples, language: .automatic)
    request.window = .init(start: Double(start), phase: .boundary)
    let update = try progress.advance(request)
    if update.action == .restart { restarts += 1 }
    #expect(update.windowOffset + 12 <= 60)
  }
  #expect(restarts == 2)
}

@Test func incrementalSpeechRejectsInvalidAndOverflowingPositionsBeforeConversion() throws {
  for start in [Double.nan, .infinity, -.infinity, -1, .greatestFiniteMagnitude] {
    var progress = SpeechIncrementalWindow()
    var request = SpeechWindowRequest(samples: [0.1], language: .automatic)
    request.window = .init(start: start, phase: .partial)
    #expect(throws: SpeechError.self) { try progress.advance(request) }
  }
  var progress = SpeechIncrementalWindow()
  var request = SpeechWindowRequest(
    samples: [Float](repeating: 0, count: 8_192), language: .automatic)
  request.window = .init(start: Double(Int64.max - 4_095) / 16_000, phase: .partial)
  #expect(throws: SpeechError.self) { try progress.advance(request) }
}
