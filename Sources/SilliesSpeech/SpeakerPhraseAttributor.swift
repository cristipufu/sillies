import Foundation
import SilliesCore

package enum SpeakerPhraseAttributor {
  package static func annotate(_ phrase: SpeechPhrase, using timeline: SpeakerActivityTimeline)
    -> [SpeechPhrase]
  {
    guard phrase.isFinal else {
      var draft = phrase
      // Recognition may finalize before speaker detection; never freeze an unlabeled draft.
      draft.finalizedThrough = nil
      return [draft]
    }
    if !phrase.words.isEmpty, !hasCompleteTimings(phrase) {
      var result = phrase
      result.speaker = .unknown
      return [result]
    }
    guard !phrase.words.isEmpty else {
      var result = phrase
      if let start = phrase.startTime, start.isFinite, let duration = phrase.duration,
        duration.isFinite, duration > 0, (start + duration).isFinite
      {
        result.speaker = timeline.speaker(in: start..<(start + duration))
      } else {
        result.speaker = .unknown
      }
      return [result]
    }
    var groups: [(speaker: TranscriptSpeaker, words: [SpeechWord])] = []
    for word in phrase.words {
      let inherited = word.boundary == .attached ? groups.last?.speaker : nil
      let speaker = inherited ?? timeline.speaker(in: word.start..<word.end)
      if groups.last?.speaker == speaker {
        groups[groups.count - 1].words.append(word)
      } else {
        groups.append((speaker, [word]))
      }
    }
    return groups.enumerated().compactMap { index, group in
      guard let first = group.words.first, let last = group.words.last else { return nil }
      var result = SpeechPhrase(
        text: SpeechWord.renderedText(group.words), isFinal: phrase.isFinal, startTime: first.start,
        duration: max(last.end - first.start, 0),
        finalizedThrough: index == groups.count - 1 ? phrase.finalizedThrough : last.end)
      result.words = group.words
      result.speaker = group.speaker
      return result
    }
  }

  private static func hasCompleteTimings(_ phrase: SpeechPhrase) -> Bool {
    guard phrase.words.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.end >= $0.start })
    else { return false }
    let timed = SpeechWord.renderedText(phrase.words)
    return timed.split(whereSeparator: \.isWhitespace)
      == phrase.text.split(whereSeparator: \.isWhitespace)
  }
}
