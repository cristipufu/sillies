import Foundation

/// Woof uses a small character vocabulary and short, independently generated text chunks.
enum WoofTextPreparation {
  private static let maximumChunkCharacters = 120
  private static let earliestPreferredBreak = maximumChunkCharacters / 2
  private static let punctuation: [Character: Character] = [
    "‘": "'", "’": "'", "“": "\"", "”": "\"", "–": "-", "−": "-",
  ]
  private static let sentenceBoundaries: Set<Character> = [".", "!", "?", ";", ":"]

  static func chunks(_ text: String) -> [String] {
    let normalized = String(text.map { punctuation[$0] ?? $0 })
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    var remaining = Array(normalized)
    var result: [String] = []
    while remaining.count > maximumChunkCharacters {
      let window = remaining.prefix(maximumChunkCharacters)
      let breaks = window.indices.filter { window[$0] == " " }
      let sentenceBreak = breaks.last {
        $0 >= earliestPreferredBreak && sentenceBoundaries.contains(window[$0 - 1])
      }
      let end = sentenceBreak ?? breaks.last ?? maximumChunkCharacters
      result.append(String(remaining[..<end]))
      remaining.removeFirst(end)
      if remaining.first == " " { remaining.removeFirst() }
    }
    if !remaining.isEmpty { result.append(String(remaining)) }
    return result
  }
}
