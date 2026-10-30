import Foundation
import SilliesCore
import XCTest

@testable import SilliesSpeech

final class SpeakerAttributionTests: XCTestCase {
  func testDraftCannotFinalizeTextBeforeItsSpeakerLabelsArrive() {
    var draft = SpeechPhrase(text: "Hello", isFinal: false, finalizedThrough: 10)
    draft.words = [.init(text: "Hello", start: 9, end: 10)]
    let result = SpeakerPhraseAttributor.annotate(draft, using: SpeakerActivityTimeline())
    XCTAssertEqual(result.count, 1)
    XCTAssertNil(result.first?.finalizedThrough)
    XCTAssertFalse(result.first?.isFinal ?? true)
  }

  func testPartiallyTimedTextIsPreservedVerbatim() {
    var phrase = SpeechPhrase(text: "Hello, unaligned words!", isFinal: true)
    phrase.words = [.init(text: "Hello", start: 0, end: 1)]
    let result = SpeakerPhraseAttributor.annotate(phrase, using: SpeakerActivityTimeline())
    XCTAssertEqual(result.first?.text, phrase.text)
    XCTAssertEqual(result.first?.speaker, .unknown)
  }

  func testInvalidWordTimingPreservesEveryWord() {
    var phrase = SpeechPhrase(text: "Keep every word.", isFinal: true)
    phrase.words = [
      .init(text: "Keep", start: 0, end: 1),
      .init(text: "every", start: .nan, end: 2),
      .init(text: "word.", start: 2, end: 3),
    ]
    let result = SpeakerPhraseAttributor.annotate(phrase, using: SpeakerActivityTimeline())
    XCTAssertEqual(result.map(\.text), [phrase.text])
    XCTAssertEqual(result.first?.speaker, .unknown)
  }

  func testWordTimesSplitSpeakerTurnsWithoutLosingPunctuationOrFinalization() throws {
    var timeline = SpeakerActivityTimeline()
    try timeline.append(
      .init(
        start: 5, frameDuration: 0.1, speakerCount: 2,
        probabilities: Array(repeating: [Float(0.9), 0.02], count: 10).flatMap { $0 }
          + Array(repeating: [Float(0.02), 0.9], count: 10).flatMap { $0 }))
    var phrase = SpeechPhrase(
      text: "Hello! Salut!", isFinal: true, startTime: 0, duration: 2, finalizedThrough: 2)
    phrase.words = [
      .init(text: "Hello", start: 0, end: 0.8),
      .init(text: "!", start: 0.8, end: 0.8, boundary: .attached),
      .init(text: "Salut!", start: 1, end: 2),
    ]
    let result = SpeakerPhraseAttributor.annotate(phrase.shifted(by: 5), using: timeline)
    XCTAssertEqual(result.map(\.text), ["Hello!", "Salut!"])
    XCTAssertEqual(result.map(\.speaker), [.identified(1), .identified(2)])
    XCTAssertEqual(result.last?.finalizedThrough, 7)
  }
}
