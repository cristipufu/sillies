import Foundation

/// Assigns identities only to complete, validated word ranges. Spoken text remains authoritative.
struct TranscriptCallAttribution {
  // Smaller than one audio sample; range construction can round a word endpoint.
  private static let timeBoundaryTolerance: TimeInterval = 0.000_001
  struct Span {
    var text: String
    var range: Range<TimeInterval>
    let name: CallSpeakerName?
  }
  let timeline: CallSpeakerTimeline
  let participant: CallSpeakerTimeline.Participant

  func spans(for segment: TranscriptSegment, words: [TranscriptWord]) -> [Span]? {
    if case .overlapping = segment.speaker {
      return [unnamed(segment)]
    }
    guard let units = validatedUnits(words, segment: segment) else {
      guard
        case .resolved(let name) = timeline.decision(
          for: segment.start..<segment.end, participant: participant)
      else { return nil }
      return [.init(text: segment.text, range: segment.start..<segment.end, name: name)]
    }
    var spans: [Span] = []
    for unit in units {
      guard
        case .resolved(let name) = timeline.decision(
          for: unit.start..<unit.end, participant: participant)
      else { return nil }
      if let last = spans.last, last.name?.comparisonKey == name?.comparisonKey {
        spans[spans.count - 1].text += " " + unit.text
        spans[spans.count - 1].range = last.range.lowerBound..<unit.end
      } else {
        spans.append(.init(text: unit.text, range: unit.start..<unit.end, name: name))
      }
    }
    // A single identity needs no structural change to the original passage or its whitespace.
    if spans.count == 1, let span = spans.first {
      return [.init(text: segment.text, range: segment.start..<segment.end, name: span.name)]
    }
    return spans
  }

  private func unnamed(_ segment: TranscriptSegment) -> Span {
    .init(text: segment.text, range: segment.start..<segment.end, name: nil)
  }

  private func validatedUnits(_ words: [TranscriptWord], segment: TranscriptSegment)
    -> [TranscriptWord]?
  {
    guard !words.isEmpty, TranscriptWord.renderedText(words) == segment.text else { return nil }
    var units: [TranscriptWord] = []
    for word in words {
      guard word.start.isFinite, word.end.isFinite,
        word.start >= segment.start - Self.timeBoundaryTolerance,
        word.end <= segment.end + Self.timeBoundaryTolerance, word.end >= word.start,
        !word.text.isEmpty
      else { return nil }
      if word.boundary == .attached, let previous = units.popLast() {
        guard word.start >= previous.start, word.end >= previous.end else { return nil }
        units.append(
          .init(text: previous.text + word.text, start: previous.start, end: word.end))
      } else {
        guard word.end > word.start, units.last.map({ word.start >= $0.end }) ?? true else {
          return nil
        }
        units.append(word)
      }
    }
    return units
  }
}
