import Foundation

/// Keep the original wording and chronology, with a bounded opening and recent context per subject.
struct MeetingExcerptSelection: Sendable {
  static let maximumPassages = 6
  private static let initialPassages = 2
  private var slices: [MeetingTranscriptSlice] = []
  var passages: [String] {
    slices.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
  }
  mutating func include(_ evidence: MeetingTopicEvidence) {
    var byOffset = Dictionary(uniqueKeysWithValues: slices.map { ($0.range.lowerBound, $0) })
    for slice in evidence.slices { byOffset[slice.range.lowerBound] = slice }
    let chronological = byOffset.values.sorted { $0.range.lowerBound < $1.range.lowerBound }
    if chronological.count <= Self.maximumPassages {
      slices = chronological
    } else {
      slices =
        Array(chronological.prefix(Self.initialPassages))
        + Array(chronological.suffix(Self.maximumPassages - Self.initialPassages))
    }
  }
}
