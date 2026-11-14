import SilliesSpeech
import Testing
import WhisperKit

@testable import SilliesSpeechWhisper

@Test func whisperShortInputEntersNativeSeekLoopWithoutChangingTheTrailingGuard() throws {
  let options = DecodingOptions()
  let guardSamples = Int(options.windowClipTime * Float(WhisperKit.sampleRate))
  for count in [1, guardSamples - 1, guardSamples, guardSamples + 1] {
    let original = [Float](repeating: 0.01, count: count)
    let prepared = try WhisperTranscriptionInput(original, options: options)
    #expect(prepared.samples.count > guardSamples)
    #expect(Array(prepared.samples.prefix(count)) == original)
    #expect(prepared.samples.dropFirst(count).allSatisfy { $0 == 0 })
    #expect(prepared.samples.count == max(count, guardSamples + 1))
  }
  #expect(try WhisperTranscriptionInput([], options: options).samples.isEmpty)
  #expect(options.windowClipTime == DecodingOptions().windowClipTime)
}

@Test func whisperInvalidNativeSeekGuardsFailRecoverably() {
  for duration: Float in [-0.0001, .nan, .infinity, Float.greatestFiniteMagnitude] {
    var options = DecodingOptions()
    options.windowClipTime = duration
    #expect(throws: SpeechError.self) {
      try WhisperTranscriptionInput([0.1], options: options)
    }
  }
}

@Test func whisperZeroAndBackwardTimestampsConsumeTheWindowAndNativeOffsetsCannotOverflow() {
  #expect(WhisperSeekProgress.advance(from: 0, proposed: 0, sampleCount: 16_001) == 16_001)
  #expect(WhisperSeekProgress.advance(from: 100, proposed: 50, sampleCount: 160) == 260)
  #expect(WhisperSeekProgress.advance(from: 100, proposed: 180, sampleCount: 160) == 180)
  #expect(WhisperSeekProgress.advance(from: Int.max - 1, proposed: 0, sampleCount: 4) == Int.max)
  #expect(WhisperSeekProgress.advance(from: -1, proposed: 0, sampleCount: 4) == Int.max)
  #expect(WhisperSeekProgress.advance(from: 0, proposed: 0, sampleCount: 0) == Int.max)
  let captured = WhisperSegmentSeeker(context: .captured)
  let extended = WhisperSegmentSeeker(context: .extended)
  #expect(captured.nextSeek(from: 0, proposed: 0, sampleCount: 16_001) == 0)
  #expect(extended.nextSeek(from: 0, proposed: 0, sampleCount: 16_001) == 16_001)
  #expect(captured.nextSeek(from: 0, proposed: 0, sampleCount: 16_001) == 0)
}

@Test func whisperNewlyPaddedResultsRequireNativeConfidenceWithoutChangingCapturedResults() {
  let options = DecodingOptions()
  let accepted = TranscriptionSegment(
    avgLogprob: options.logProbThreshold ?? -1,
    compressionRatio: options.compressionRatioThreshold ?? 2.4,
    words: [.init(word: "Okay.", tokens: [], start: 0, end: 0.4, probability: 0.9)])
  let rejected = [
    TranscriptionSegment(avgLogprob: -13.6),
    TranscriptionSegment(compressionRatio: 10),
    TranscriptionSegment(avgLogprob: .nan),
    TranscriptionSegment(compressionRatio: .infinity),
  ]
  let native = TranscriptionResult(
    text: "", segments: [accepted] + rejected, language: "en", timings: .init())
  let padded = WhisperDecodingOutcome(
    nativeResults: [native], context: .extended, options: options)
  let captured = WhisperDecodingOutcome(
    nativeResults: [native], context: .captured, options: options)
  #expect(padded.acceptedSegments == [accepted])
  #expect(captured.acceptedSegments.count == 1 + rejected.count)
  #expect(padded.result.words.map(\.text) == ["Okay."])
  #expect(padded.result.detectedLanguage == "en")
}
