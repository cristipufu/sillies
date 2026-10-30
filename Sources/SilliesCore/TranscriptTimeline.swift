import Foundation

/// Revisions replace their audio range; finalization never changes a passage's chronological position.
public struct TranscriptTimeline: Sendable {
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
  private var sources: [String: TranscriptSourceTimeline] = [:]
  private var markers = TranscriptSourceTimeline()
  private var nextSequence = 0
  public private(set) var revision: UInt64 = 0

  public init() {}

  public var text: String {
    render(sources.values.flatMap(\.entries) + markers.entries)
  }

  /// Reads only each source's recent tail, regardless of how long the session has run.
  public func preview(characterLimit: Int) -> String {
    guard characterLimit > 0 else { return "" }
    let recent =
      sources.values.flatMap { $0.recentEntries(characterLimit: characterLimit) }
      + markers.recentEntries(characterLimit: characterLimit)
    return renderPreview(recent, characterLimit: characterLimit)
  }

  private func renderPreview(_ entries: [TranscriptSourceTimeline.Entry], characterLimit: Int)
    -> String
  {
    var remaining = characterLimit
    var fragments: [Substring] = []
    let ordered = entries.sorted(by: TranscriptSourceTimeline.Entry.chronologicalOrder)
    for entry in ordered.reversed() {
      let count = min(remaining, entry.characterCount)
      fragments.append(entry.renderedText.suffix(count))
      remaining -= count
      if remaining <= 0 { break }
      remaining -= 1
    }
    return fragments.reversed().joined(separator: "\n")
  }

  private func render(_ entries: [TranscriptSourceTimeline.Entry]) -> String {
    entries.sorted(by: TranscriptSourceTimeline.Entry.chronologicalOrder)
      .map(\.renderedText).joined(separator: "\n")
  }

  public mutating func receive(_ passage: Passage) {
    let sequence = reserveSequence()
    if sources[passage.source, default: TranscriptSourceTimeline()].receive(
      passage, sequence: sequence)
    {
      revision &+= 1
    }
  }

  public mutating func preservePending() {
    for source in sources.keys { sources[source]?.preservePending() }
  }

  public mutating func markLanguage(_ name: String, at time: TimeInterval) {
    markers.insertMarker(.init(language: name, time: time, sequence: reserveSequence()))
    revision &+= 1
  }

  private mutating func reserveSequence() -> Int {
    defer { nextSequence += 1 }
    return nextSequence
  }
}
