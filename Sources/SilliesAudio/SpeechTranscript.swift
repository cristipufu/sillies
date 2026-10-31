import Foundation
import SilliesCore
import SilliesSpeech

struct SpeechTranscript {
  private static let previewCharacterLimit = 8_192
  private static let untimedPhraseDuration: TimeInterval = 0.001
  private var timeline = TranscriptTimeline()
  private var pendingStarts: [SessionAudioSource: TimeInterval] = [:]
  private var previewRevision: UInt64?
  private var cachedPreview = ""

  var text: String { timeline.text }
  var segments: [TranscriptSegment] { timeline.segments }

  var preview: String {
    mutating get {
      if previewRevision != timeline.revision {
        cachedPreview = timeline.preview(characterLimit: Self.previewCharacterLimit)
        previewRevision = timeline.revision
      }
      return cachedPreview
    }
  }

  static func preview(of text: String) -> String {
    String(text.suffix(previewCharacterLimit))
  }

  mutating func receive(_ phrase: SpeechPhrase, source: SessionAudioSource, elapsed: TimeInterval) {
    let start = phrase.startTime ?? pendingStarts[source] ?? elapsed
    let duration = max(phrase.duration ?? Self.untimedPhraseDuration, Self.untimedPhraseDuration)
    guard start.isFinite, duration.isFinite, start >= 0 else { return }
    timeline.receive(
      .init(
        source: source.rawValue, range: start..<(start + duration),
        text: phrase.text, isFinal: phrase.isFinal, finalizedThrough: phrase.finalizedThrough,
        speaker: phrase.speaker))
    pendingStarts[source] = phrase.isFinal ? nil : start
  }

  mutating func preserveDrafts() {
    timeline.preservePending()
    pendingStarts.removeAll()
  }

  mutating func markLanguage(_ name: String, elapsed: TimeInterval) {
    timeline.markLanguage(name, at: elapsed)
  }
}
