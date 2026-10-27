import Foundation

/// Revisions replace their audio range; finalization never changes a passage's chronological position.
public struct TranscriptTimeline: Sendable {
  // Smaller than an audio sample; absorbs rounding when CMTime becomes seconds.
  private static let timeBoundaryTolerance: TimeInterval = 0.000_001

  public struct Passage: Sendable {
    public let source: String
    public let range: Range<TimeInterval>
    public let text: String
    public let isFinal: Bool
    public let finalizedThrough: TimeInterval?

    public init(
      source: String, range: Range<TimeInterval>, text: String, isFinal: Bool,
      finalizedThrough: TimeInterval? = nil
    ) {
      self.source = source
      self.range = range
      self.text = text
      self.isFinal = isFinal
      self.finalizedThrough = finalizedThrough
    }
  }
  private struct Entry: Sendable {
    let sequence: Int
    let source: String?
    let range: Range<TimeInterval>
    var text: String
    var isFinal: Bool
  }
  private var entries: [Entry] = []
  private var nextSequence = 0

  public init() {}

  public var text: String {
    entries.sorted {
      if $0.range.lowerBound != $1.range.lowerBound {
        return $0.range.lowerBound < $1.range.lowerBound
      }
      return $0.sequence < $1.sequence
    }.map { entry in
      let label = entry.source.map { "\($0): " } ?? ""
      return "[\(SessionRecord.formatDuration(entry.range.lowerBound))] \(label)\(entry.text)"
    }.joined(separator: "\n")
  }

  public mutating func receive(_ passage: Passage) {
    let overlaps: (Entry) -> Bool = {
      guard $0.source == passage.source else { return false }
      let sharedDuration =
        min($0.range.upperBound, passage.range.upperBound)
        - max($0.range.lowerBound, passage.range.lowerBound)
      return sharedDuration > Self.timeBoundaryTolerance
        || abs($0.range.lowerBound - passage.range.lowerBound) <= Self.timeBoundaryTolerance
    }
    if entries.contains(where: { overlaps($0) && $0.isFinal }) { return }
    let sequence = entries.first(where: overlaps)?.sequence ?? reserveSequence()
    entries.removeAll(where: overlaps)
    let text = passage.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty {
      entries.append(
        Entry(
          sequence: sequence, source: passage.source, range: passage.range, text: text,
          isFinal: passage.isFinal))
    }
    if let through = passage.finalizedThrough {
      for index in entries.indices
      where entries[index].source == passage.source
        && entries[index].range.upperBound <= through + Self.timeBoundaryTolerance
      {
        entries[index].isFinal = true
      }
    }
  }

  public mutating func preservePending() {
    for index in entries.indices { entries[index].isFinal = true }
  }

  public mutating func markLanguage(_ name: String, at time: TimeInterval) {
    entries.append(
      Entry(
        sequence: reserveSequence(), source: nil, range: time..<time, text: "Language: \(name)",
        isFinal: true))
  }

  private mutating func reserveSequence() -> Int {
    defer { nextSequence += 1 }
    return nextSequence
  }
}
