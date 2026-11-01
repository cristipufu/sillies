import Foundation

/// Incremental, lossless segmentation. Keep a lookahead character for decimals and abbreviations.
public struct SpokenPhraseBuffer: Sendable {
  public static let maximumPhraseCharacters = 180
  private static let minimumClauseCharacters = 48
  private static let sentenceMarks = Set<Character>(".!?。！？\n")
  private static let clauseMarks = Set<Character>(",;:，；：")
  private var pending = ""
  public init() {}

  public mutating func append(_ delta: String) -> [String] {
    pending += delta
    var result: [String] = []
    while let boundary = boundary() {
      let phrase = String(pending[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
      pending = String(pending[boundary...])
      if !phrase.isEmpty { result.append(phrase) }
    }
    return result
  }
  public mutating func finish() -> [String] {
    let remainder = pending.trimmingCharacters(in: .whitespacesAndNewlines)
    pending = ""
    return remainder.isEmpty
      ? [] : SpokenTextChunks.split(remainder, maximumCharacters: Self.maximumPhraseCharacters)
  }
  private func boundary() -> String.Index? {
    let characters = Array(pending)
    guard characters.count > 1 else { return nil }
    for index in 0..<min(characters.count - 1, Self.maximumPhraseCharacters) {
      let current = characters[index]
      let next = characters[index + 1]
      let sentence = Self.sentenceMarks.contains(current)
      let clause = index >= Self.minimumClauseCharacters && Self.clauseMarks.contains(current)
      if sentence || clause {
        guard next.isWhitespace || "。！？".contains(current) else { continue }
        if current == "." {
          let prefix = String(characters[...index])
          let word = prefix.split(whereSeparator: \.isWhitespace).last ?? ""
          // Initials and short abbreviations need more context. No language-specific word list.
          if word.filter(\.isLetter).count <= 3 || word.dropLast().contains(".") { continue }
        }
        return pending.index(pending.startIndex, offsetBy: index + 1)
      }
    }
    guard characters.count > Self.maximumPhraseCharacters else { return nil }
    let prefix = characters.prefix(Self.maximumPhraseCharacters)
    let count =
      prefix.lastIndex(where: \.isWhitespace).map { $0 + 1 } ?? Self.maximumPhraseCharacters
    return pending.index(pending.startIndex, offsetBy: count)
  }
}
