import Foundation
import XCTest

@testable import SilliesSpeech

final class SpeechWindowTests: XCTestCase {
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

  private func window(start: Double, duration: Double, completion: SpeechWindowBuffer.Completion)
    -> SpeechWindowBuffer.Window
  {
    .init(
      samples: [Float](repeating: 0.1, count: Int(duration * 16_000)), start: start,
      completion: completion)
  }
}
