import Foundation

public struct VocabularyEntry: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public var phrase: String
  public var heardAs: String
  public init(id: UUID = UUID(), phrase: String, heardAs: String = "") {
    self.id = id
    self.phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
    self.heardAs = heardAs.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// Explicit, whole-word replacements. Matches use the original text, so rules never cascade.
public struct PersonalDictionary: Sendable {
  public static let maximumEntries = 100
  public static let maximumPhraseLength = 100
  public let entries: [VocabularyEntry]
  public init(entries: [VocabularyEntry]) {
    self.entries = Array(
      entries.filter {
        !$0.phrase.isEmpty && $0.phrase.count <= Self.maximumPhraseLength
          && $0.heardAs.count <= Self.maximumPhraseLength
      }.prefix(Self.maximumEntries))
  }
  public var hints: [String] { entries.map(\.phrase) }

  public func replacing(in source: String) -> String {
    struct Match {
      let range: Range<String.Index>
      let replacement: String
    }
    var matches: [Match] = []
    for entry in entries where !entry.heardAs.isEmpty {
      var start = source.startIndex
      while start < source.endIndex,
        let range = source.range(
          of: entry.heardAs, options: .caseInsensitive, range: start..<source.endIndex)
      {
        let left =
          range.lowerBound == source.startIndex
          || !Self.isWord(source[source.index(before: range.lowerBound)])
        let right = range.upperBound == source.endIndex || !Self.isWord(source[range.upperBound])
        if left && right { matches.append(.init(range: range, replacement: entry.phrase)) }
        start = range.upperBound
      }
    }
    matches.sort {
      $0.range.lowerBound == $1.range.lowerBound
        ? $0.range.upperBound > $1.range.upperBound : $0.range.lowerBound < $1.range.lowerBound
    }
    var output = ""
    var cursor = source.startIndex
    for match in matches where match.range.lowerBound >= cursor {
      output += source[cursor..<match.range.lowerBound]
      output += match.replacement
      cursor = match.range.upperBound
    }
    output += source[cursor...]
    return output
  }

  private static func isWord(_ character: Character) -> Bool {
    character.isLetter || character.isNumber || character == "_"
  }
}
