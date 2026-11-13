import Foundation

/// Original sentence ranges remain attached while topic-specific evidence is admitted in smaller batches.
struct MeetingTopicEvidence: Sendable {
  struct Source: Sendable {
    private struct Passage: Sendable {
      let slice: MeetingTranscriptSlice
      let identity: MeetingTopicIdentity
    }
    private static let followingContextSentences = 1
    private let passages: [Passage]
    private let topics: [MeetingTopicIdentity]
    init(_ source: MeetingTranscriptSlice, topicTitles: [String] = []) {
      topics = topicTitles.map(MeetingTopicIdentity.init)
      passages = source.sentences().map { .init(slice: $0, identity: .init($0.text)) }
    }
    func matching(_ title: String) -> MeetingTopicEvidence {
      let identity = MeetingTopicIdentity(title)
      let otherTopics = topics.filter { !$0.sharesAnchor(with: identity) }
      var selected: Set<Int> = []
      for index in passages.indices where passages[index].identity.sharesAnchor(with: identity) {
        selected.insert(index)
        guard
          passages[index].slice.text.trimmingCharacters(in: .whitespaces).last?.isNewline != true
        else { continue }
        let end = min(passages.count, index + Self.followingContextSentences + 1)
        for context in (index + 1)..<end {
          let candidate = passages[context].identity
          if candidate.sharesAnchor(with: identity)
            || !otherTopics.contains(where: { candidate.sharesAnchor(with: $0) })
          {
            selected.insert(context)
          }
        }
      }
      return .init(slices: selected.sorted().map { passages[$0].slice })
    }

  }
  let slices: [MeetingTranscriptSlice]
  var isEmpty: Bool { slices.isEmpty }
  var text: String { slices.map(\.text).joined(separator: "\n") }
  var range: Range<Int>? {
    guard let first = slices.first, let last = slices.last else { return nil }
    return first.range.lowerBound..<last.range.upperBound
  }
  private init(slices: [MeetingTranscriptSlice]) { self.slices = slices }
  func halves() -> (first: Self, last: Self)? {
    if slices.count > 1 {
      let middle = slices.count / 2
      return (.init(slices: Array(slices[..<middle])), .init(slices: Array(slices[middle...])))
    }
    guard let slice = slices.first, let halves = slice.halves() else { return nil }
    return (.init(slices: [halves.first]), .init(slices: [halves.last]))
  }
}
