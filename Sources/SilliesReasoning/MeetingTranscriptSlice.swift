import Foundation

/// Source ranges belong to the captured transcript, never to generated text.
struct MeetingTranscriptSlice: Sendable {
  private static let spacingDependentTerminators: Set<Character> = [".", "!", "?"]
  private static let standaloneTerminators: Set<Character> = ["。", "！", "？"]
  let text: String
  let range: Range<Int>
  init(text: String, offset: Int) {
    self.text = text
    range = offset..<(offset + text.count)
  }

  func sentences() -> [Self] {
    var sentences: [Self] = []
    text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) {
      passage, range, _, _ in
      guard let passage, !passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return
      }
      let offset =
        self.range.lowerBound + text.distance(from: text.startIndex, to: range.lowerBound)
      sentences.append(.init(text: passage, offset: offset))
    }
    return sentences
  }

  func halves() -> (first: Self, last: Self)? {
    guard text.count > 1,
      let first = Self.boundedPrefix(in: text[...], maximumCharacters: text.count / 2),
      !first.isEmpty, first.count < text.count
    else { return nil }
    return (
      .init(text: first, offset: range.lowerBound),
      .init(text: String(text.dropFirst(first.count)), offset: range.lowerBound + first.count)
    )
  }

  static func boundedPrefix(in source: Substring, maximumCharacters: Int) -> String? {
    let prefix = source.prefix(maximumCharacters)
    guard prefix.endIndex != source.endIndex else { return String(prefix) }
    if let boundary = prefix.indices.last(where: { isSentenceBoundary(at: $0, in: source) }) {
      let end = source.index(after: boundary)
      if source.distance(from: source.startIndex, to: end) >= maximumCharacters / 2 {
        return String(source[..<end])
      }
    }
    guard let boundary = prefix.lastIndex(where: \.isWhitespace) else { return nil }
    return String(source[..<source.index(after: boundary)])
  }

  private static func isSentenceBoundary(at index: String.Index, in source: Substring) -> Bool {
    let character = source[index]
    if character.isNewline || standaloneTerminators.contains(character) { return true }
    guard spacingDependentTerminators.contains(character) else { return false }
    let next = source.index(after: index)
    return next == source.endIndex || source[next].isWhitespace
  }
}
