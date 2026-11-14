import Foundation
import SilliesCore
import XCTest

@testable import SilliesSpeech

final class SpeechWindowTests: XCTestCase {
  func testBacklogReadsPreserveShortVoicedFramesInsideSilence() throws {
    var buffer = SpeechWindowBuffer()
    let quietFrame = [Float](repeating: 0.003, count: 160)
    let silence = [Float](repeating: 0, count: 1_440)
    try buffer.appendAnalysisFrames(quietFrame + silence)
    let window = try XCTUnwrap(buffer.next(mode: .draining))
    XCTAssertEqual(Array(window.samples.prefix(160)), quietFrame)
    XCTAssertEqual(window.start, 0)
  }
  func testWordAttachmentsPreservePunctuationAndHyphens() {
    var transcript = SpeechWindowTranscript()
    let result = transcript.receive(
      .init(words: [
        .init(text: "customer", start: 0, end: 1),
        .init(text: "follow", start: 1, end: 2),
        .init(text: "-up", start: 2, end: 2.4, boundary: .attached),
        .init(text: ".", start: 2.4, end: 2.5, boundary: .attached),
      ]), window: window(start: 0, duration: 3, completion: .session))
    XCTAssertEqual(result.phrases.first?.text, "customer follow-up.")
  }

  func testSpeechBoundarySurvivesNewSpeechArrivingDuringInference() throws {
    var buffer = SpeechWindowBuffer()
    try buffer.append([Float](repeating: 0.1, count: 16_000))
    try buffer.append([Float](repeating: 0, count: 9_600))
    try buffer.append([Float](repeating: 0.1, count: 16_000))
    try buffer.append([Float](repeating: 0, count: 9_600))
    let first = try XCTUnwrap(buffer.next(mode: .live))
    XCTAssertEqual(first.completion, .utterance)
    XCTAssertEqual(first.end, 1.6, accuracy: 0.0001)
    buffer.retire(first, through: first.end)
    let second = try XCTUnwrap(buffer.next(mode: .live))
    XCTAssertEqual(second.start, first.end, accuracy: 0.0001)
    XCTAssertEqual(second.end, 3.2, accuracy: 0.0001)
  }
  func testSilenceStaysBoundedAcrossEightVirtualHours() throws {
    var buffer = SpeechWindowBuffer()
    let silence = [Float](repeating: 0, count: 16_000)
    for _ in 0..<(8 * 60 * 60) {
      try buffer.append(silence)
      XCTAssertNil(buffer.next(mode: .live))
      XCTAssertLessThanOrEqual(buffer.samples.count, 3_200)
    }
    XCTAssertNil(buffer.next(mode: .draining))
    XCTAssertTrue(buffer.samples.isEmpty)
  }

  func testSlowInferenceRejectsOverflowWithoutGrowingBuffer() throws {
    var buffer = SpeechWindowBuffer()
    try buffer.append([Float](repeating: 0.1, count: 24 * 16_000))
    XCTAssertThrowsError(try buffer.append([0.1]))
    XCTAssertEqual(buffer.samples.count, 24 * 16_000)
  }

  func testWindowBoundaryPreservesUncommittedWordsAndRepeatedSpeech() throws {
    var transcript = SpeechWindowTranscript()
    let first = transcript.receive(
      .init(words: [
        .init(text: "yes", start: 1, end: 2), .init(text: "yes", start: 10, end: 10.5),
        .init(text: "tomorrow", start: 11, end: 11.8),
      ]), window: window(start: 0, duration: 12, completion: .boundary))
    XCTAssertEqual(first.phrases.map(\.text), ["yes yes", "tomorrow"])
    let next = transcript.receive(
      .init(words: [
        .init(text: "yes", start: 0, end: 0.25),
        .init(text: "tomorrow", start: 0.7, end: 1.5),
        .init(text: "yes", start: 2, end: 2.5),
      ]), window: window(start: 10.3, duration: 4, completion: .utterance))
    XCTAssertEqual(next.phrases.map(\.text), ["tomorrow yes"])
    XCTAssertEqual(next.retiredThrough, 14.3, accuracy: 0.0001)
  }

  func testEmptyFinalClearsDraftAndAdvancesTime() {
    var transcript = SpeechWindowTranscript()
    _ = transcript.receive(
      .init(words: [.init(text: "draft", start: 0, end: 1)]),
      window: window(start: 0, duration: 2, completion: .draft))
    let final = transcript.receive(
      .init(words: []), window: window(start: 0, duration: 3, completion: .session))
    XCTAssertEqual(final.phrases.first?.text, "")
    XCTAssertEqual(final.phrases.first?.finalizedThrough, 3)
    XCTAssertEqual(final.phrases.first?.startTime, 0)
  }

  func testShortFirstWordIsNotDiscarded() {
    var transcript = SpeechWindowTranscript()
    let result = transcript.receive(
      .init(words: [.init(text: "a", start: 0, end: 0.05)]),
      window: window(start: 0, duration: 1, completion: .session))
    XCTAssertEqual(result.phrases.first?.text, "a")
  }

  func testZeroDurationOpeningWordSurvivesDraftAndFinalWithoutRepeatingOverlap() {
    var transcript = SpeechWindowTranscript()
    let words: [SpeechWord] = [
      .init(text: "Am", start: 0, end: 0),
      .init(text: "stabilit", start: 0, end: 0.5),
    ]
    let draft = transcript.receive(
      .init(words: words),
      window: window(start: 0, duration: 1, completion: .draft))
    XCTAssertEqual(draft.phrases.first?.text, "Am stabilit")
    let final = transcript.receive(
      .init(words: words),
      window: window(start: 0, duration: 1, completion: .utterance))
    XCTAssertEqual(final.phrases.first?.text, "Am stabilit")
    let overlap = transcript.receive(
      .init(words: words),
      window: window(start: 0, duration: 1, completion: .session))
    XCTAssertEqual(overlap.phrases.first?.text, "")
  }

  func testAdaptiveBoundaryKeepsShortAnswersAndTheFinalPartialFrame() throws {
    for mode in SpeechBoundaryPolicy.Mode.allCases {
      var buffer = SpeechWindowBuffer()
      buffer.boundaries = .init(mode: mode)
      try buffer.appendAnalysisFrames([Float](repeating: 0, count: 4_800))
      let answer = [Float](repeating: 0.03, count: 3_200 + 17)
      try buffer.appendAnalysisFrames(answer)
      let result = try XCTUnwrap(buffer.next(mode: .draining))
      XCTAssertEqual(Array(result.samples.suffix(answer.count)), answer)
      XCTAssertEqual(result.end, Double(4_800 + answer.count) / 16_000, accuracy: 0.000001)
    }
  }

  func testAdaptiveBoundaryPreservesTheMaximumWindowAndItsTail() throws {
    var buffer = SpeechWindowBuffer()
    buffer.boundaries = .init(mode: .adaptive)
    var audio = [Float](repeating: 0.1, count: 12 * 16_000)
    let dip = 11 * 16_000
    audio.replaceSubrange(dip..<dip + 1_600, with: repeatElement(0, count: 1_600))
    audio.replaceSubrange(dip + 640..<dip + 800, with: repeatElement(0.003, count: 160))
    try buffer.appendAnalysisFrames(audio)
    let window = try XCTUnwrap(buffer.next(mode: .live))
    XCTAssertEqual(window.end, SpeechWindowBuffer.maximumWindowDuration)
    buffer.retire(window, through: window.end)
    let tail = try XCTUnwrap(buffer.next(mode: .draining))
    XCTAssertLessThan(tail.start, window.end)
    XCTAssertEqual(tail.samples.last, audio.last)
  }

  func testNonFiniteSpeechSamplesFailWithoutRetainingInvalidAudio() {
    var buffer = SpeechWindowBuffer()
    XCTAssertThrowsError(try buffer.append([.nan]))
    XCTAssertTrue(buffer.samples.isEmpty)
  }

  func testBoundaryReplayRetainsConfiguredDecoderHistoryWithoutGrowingTheWindow() throws {
    var buffer = SpeechWindowBuffer()
    buffer.boundaryReplayDuration = 5.6
    let count = Int(SpeechWindowBuffer.maximumWindowDuration * SpeechWindowBuffer.sampleRate)
    try buffer.append([Float](repeating: 0.1, count: count))
    let first = try XCTUnwrap(buffer.next(mode: .catchingUp))
    buffer.retire(first, through: 10)
    let tail = try XCTUnwrap(buffer.next(mode: .draining))
    XCTAssertEqual(tail.start, 4.4, accuracy: 0.0001)
    XCTAssertLessThanOrEqual(tail.samples.count, count)
    XCTAssertEqual(tail.end, first.end, accuracy: 0.0001)
  }

  func testBoundaryAlwaysRetiresAudioWhenRecognizedWordsPrecedeReplayContext() throws {
    for replay in [SpeechWindowConfiguration.leadingContext, 5.6] {
      var buffer = SpeechWindowBuffer()
      buffer.boundaryReplayDuration = replay
      let count = Int(SpeechWindowBuffer.maximumWindowDuration * SpeechWindowBuffer.sampleRate)
      try buffer.append([Float](repeating: 0.1, count: count))
      let first = try XCTUnwrap(buffer.next(mode: .catchingUp))
      buffer.retire(first, through: first.start)
      XCTAssertGreaterThan(buffer.retainedStartSample, 0)
      XCTAssertLessThan(buffer.samples.count, count)
    }
  }

  func testContinuousWordClockPreservesShortWordsAndRepeatedWordsAcrossARollover() {
    var transcript = SpeechWindowTranscript()
    _ = transcript.receive(
      .init(words: [.init(text: "yes", start: 10.7, end: 10.76)], timing: .continuous),
      window: window(start: 0, duration: 12, completion: .boundary))
    let result = transcript.receive(
      .init(
        words: [
          .init(text: "yes", start: 0.14, end: 0.20),
          .init(text: "yes", start: 0.19, end: 0.27),
          .init(text: "no", start: 0.28, end: 0.35),
        ], timing: .continuous),
      window: window(start: 10.56, duration: 3, completion: .utterance))
    XCTAssertEqual(result.phrases.first?.text, "yes no")
  }

  private func window(start: Double, duration: Double, completion: SpeechWindowBuffer.Completion)
    -> SpeechWindowBuffer.Window
  {
    .init(
      samples: [Float](repeating: 0.1, count: Int(duration * 16_000)), start: start,
      completion: completion)
  }
}
