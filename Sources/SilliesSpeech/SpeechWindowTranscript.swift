import Foundation

/// Commits words by their audio positions. Repeated words later in the audio remain intact.
struct SpeechWindowTranscript {
  private static let overlapDuration: TimeInterval = 1
  private static let timestampTolerance: TimeInterval = 0.08
  private var committedThrough: TimeInterval = 0
  private var lastCommittedWord: SpeechWord?

  mutating func receive(_ result: SpeechWindowResult, window: SpeechWindowBuffer.Window) -> (
    phrases: [SpeechPhrase], retiredThrough: TimeInterval
  ) {
    var words = result.words.compactMap { word -> SpeechWord? in
      let start = window.start + word.start
      let end = min(window.end, window.start + word.end)
      guard start.isFinite, end.isFinite, end >= start,
        end > committedThrough + (lastCommittedWord == nil ? 0 : Self.timestampTolerance)
      else { return nil }
      return SpeechWord(
        text: word.text, start: max(window.start, start), end: end, boundary: word.boundary)
    }
    if let previous = lastCommittedWord, let first = words.first,
      first.start < committedThrough, first.end < committedThrough + Self.overlapDuration,
      first.text.trimmingCharacters(in: .punctuationCharacters).lowercased()
        == previous.text.trimmingCharacters(in: .punctuationCharacters).lowercased()
    {
      words.removeFirst()
    }
    guard window.completion != .draft else {
      return (
        [
          phrase(
            words, start: max(window.start, committedThrough), end: window.end, finality: .draft)
        ], committedThrough
      )
    }
    let cutoff = window.completion == .boundary ? window.end - Self.overlapDuration : window.end
    let finalWords = words.filter { $0.end <= cutoff }
    let boundary = window.completion == .boundary ? (finalWords.last?.end ?? cutoff) : window.end
    var phrases = [
      phrase(
        finalWords, start: max(window.start, committedThrough), end: boundary, finality: .final)
    ]
    committedThrough = max(committedThrough, boundary)
    if let last = finalWords.last { lastCommittedWord = last }
    let draftWords = words.filter { $0.end > boundary }
    if !draftWords.isEmpty {
      phrases.append(phrase(draftWords, start: boundary, end: window.end, finality: .draft))
    }
    return (phrases, boundary)
  }

  private enum Finality { case draft, final }
  private func phrase(
    _ words: [SpeechWord], start: TimeInterval, end: TimeInterval, finality: Finality
  ) -> SpeechPhrase {
    var phrase = SpeechPhrase(
      text: SpeechWord.renderedText(words), isFinal: finality == .final, startTime: start,
      duration: max(0, end - start), finalizedThrough: finality == .final ? end : nil)
    phrase.words = words
    return phrase
  }

}
