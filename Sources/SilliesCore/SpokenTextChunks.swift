import Foundation

/// Preserve every word, preferring sentence and word boundaries within the runtime's input limit.
public enum SpokenTextChunks {
  public static func split(_ text: String, maximumCharacters: Int) -> [String] {
    guard maximumCharacters > 0 else { return [] }
    var remaining = text[...]
    var chunks: [String] = []
    while !remaining.isEmpty {
      let limit =
        remaining.index(
          remaining.startIndex, offsetBy: maximumCharacters, limitedBy: remaining.endIndex)
        ?? remaining.endIndex
      let prefix = remaining[..<limit]
      let boundary: String.Index
      if limit == remaining.endIndex {
        boundary = limit
      } else if let sentence = prefix.lastIndex(where: { ".!?。！？\n".contains($0) }) {
        boundary = remaining.index(after: sentence)
      } else if let space = prefix.lastIndex(where: \.isWhitespace), space != remaining.startIndex {
        boundary = remaining.index(after: space)
      } else {
        boundary = limit
      }
      let chunk = remaining[..<boundary].trimmingCharacters(in: .whitespacesAndNewlines)
      if !chunk.isEmpty { chunks.append(chunk) }
      remaining = remaining[boundary...]
    }
    return chunks
  }
}
