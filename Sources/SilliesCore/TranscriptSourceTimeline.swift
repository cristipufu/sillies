import Foundation

/// A source's passages never overlap, so revisions find their range without scanning the history.
struct TranscriptSourceTimeline: Sendable {
  struct Entry: Sendable {
    let sequence: Int
    let range: Range<TimeInterval>
    let renderedText: String
    let segment: TranscriptSegment?
    let characterCount: Int
    var isFinal: Bool

    init(passage: TranscriptTimeline.Passage, sequence: Int) {
      self.sequence = sequence
      segment = TranscriptSegment(
        sequence: sequence, source: passage.source,
        start: passage.range.lowerBound, end: passage.range.upperBound,
        text: passage.text, speaker: passage.speaker)
      range = passage.range
      let time = SessionRecord.formatDuration(range.lowerBound)
      let label = passage.speaker.map { passage.source + " · " + $0.label } ?? passage.source
      renderedText = "[\(time)] \(label): \(passage.text)"
      characterCount = renderedText.count
      isFinal = passage.isFinal
    }

    init(language: String, time: TimeInterval, sequence: Int) {
      segment = nil
      self.sequence = sequence
      range = time..<time
      renderedText = "[\(SessionRecord.formatDuration(time))] Language: \(language)"
      characterCount = renderedText.count
      isFinal = true
    }

    static func chronologicalOrder(_ lhs: Self, _ rhs: Self) -> Bool {
      if lhs.range.lowerBound != rhs.range.lowerBound {
        return lhs.range.lowerBound < rhs.range.lowerBound
      }
      return lhs.sequence < rhs.sequence
    }

    func overlaps(_ other: Range<TimeInterval>) -> Bool {
      let sharedDuration =
        min(range.upperBound, other.upperBound) - max(range.lowerBound, other.lowerBound)
      return sharedDuration > TranscriptSourceTimeline.timeBoundaryTolerance
        || abs(range.lowerBound - other.lowerBound)
          <= TranscriptSourceTimeline.timeBoundaryTolerance
    }
  }

  // Smaller than an audio sample; absorbs rounding when CMTime becomes seconds.
  private static let timeBoundaryTolerance: TimeInterval = 0.000_001
  private(set) var entries: [Entry] = []
  private var finalizedPrefixCount = 0

  private struct Replacement {
    let range: Range<Int>
    let entry: Entry?
  }

  mutating func receive(_ passage: TranscriptTimeline.Passage, sequence: Int) -> Bool {
    defer { finalize(through: passage.finalizedThrough) }
    guard let replacement = replacement(for: passage, sequence: sequence) else { return false }
    return apply(replacement)
  }

  private func replacement(for passage: TranscriptTimeline.Passage, sequence: Int) -> Replacement? {
    let affected = overlappingRange(passage.range)
    guard !entries[affected].contains(where: \.isFinal) else { return nil }
    let text = passage.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = TranscriptTimeline.Passage(
      source: passage.source, range: passage.range, text: text, isFinal: passage.isFinal,
      speaker: passage.speaker)
    let entry = Entry(passage: normalized, sequence: entries[affected].first?.sequence ?? sequence)
    return Replacement(range: affected, entry: text.isEmpty ? nil : entry)
  }

  private mutating func apply(_ replacement: Replacement) -> Bool {
    let affected = replacement.range
    let entry = replacement.entry
    let unchanged =
      affected.count == 1 && entries[affected.lowerBound].range == entry?.range
      && entries[affected.lowerBound].renderedText == entry?.renderedText
    if unchanged, let entry {
      entries[affected.lowerBound].isFinal = entry.isFinal
      return false
    }
    guard !affected.isEmpty || entry != nil else { return false }
    entries.replaceSubrange(affected, with: entry.map { [$0] } ?? [])
    finalizedPrefixCount = min(finalizedPrefixCount, affected.lowerBound)
    return true
  }

  mutating func insertMarker(_ entry: Entry) {
    var index = insertionIndex(at: entry.range.lowerBound)
    while index < entries.count, entries[index].range.lowerBound == entry.range.lowerBound {
      index += 1
    }
    entries.insert(entry, at: index)
  }

  mutating func preservePending() {
    for index in finalizedPrefixCount..<entries.count { entries[index].isFinal = true }
    finalizedPrefixCount = entries.count
  }

  func recentEntries(characterLimit: Int) -> [Entry] {
    var remaining = characterLimit
    var recent: [Entry] = []
    for entry in entries.reversed() {
      recent.append(entry)
      remaining -= entry.characterCount
      if remaining <= 0 { break }
      remaining -= 1
    }
    return recent
  }

  private func overlappingRange(_ range: Range<TimeInterval>) -> Range<Int> {
    var first = insertionIndex(at: range.lowerBound - Self.timeBoundaryTolerance)
    if first > 0, entries[first - 1].overlaps(range) { first -= 1 }
    var end = first
    while end < entries.count, entries[end].overlaps(range) { end += 1 }
    return first..<end
  }

  private func insertionIndex(at time: TimeInterval) -> Int {
    var lower = 0
    var upper = entries.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if entries[middle].range.lowerBound < time { lower = middle + 1 } else { upper = middle }
    }
    return lower
  }

  private mutating func finalize(through time: TimeInterval?) {
    while finalizedPrefixCount < entries.count {
      let entry = entries[finalizedPrefixCount]
      guard
        entry.isFinal
          || time.map({ entry.range.upperBound <= $0 + Self.timeBoundaryTolerance }) == true
      else { break }
      entries[finalizedPrefixCount].isFinal = true
      finalizedPrefixCount += 1
    }
  }
}
