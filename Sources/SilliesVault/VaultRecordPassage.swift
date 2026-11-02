import Foundation
import SilliesCore

/// Selects bounded evidence without letting an early, broad keyword hide a later relevant passage.
struct VaultRecordPassage {
  static let maximumCharacters = 1_600
  private static let windowStride = maximumCharacters / 2
  private static let maximumQueryTerms = 8

  struct Coverage: Encodable {
    let startOffset: Int
    let endOffset: Int
    let totalCharacters: Int
    var nextOffset: Int? { endOffset < totalCharacters ? endOffset : nil }
    var isComplete: Bool { startOffset == 0 && endOffset == totalCharacters }

    private enum CodingKeys: String, CodingKey {
      case startOffset, endOffset, totalCharacters, nextOffset, isComplete
    }
    func encode(to encoder: any Encoder) throws {
      var values = encoder.container(keyedBy: CodingKeys.self)
      try values.encode(startOffset, forKey: .startOffset)
      try values.encode(endOffset, forKey: .endOffset)
      try values.encode(totalCharacters, forKey: .totalCharacters)
      try values.encodeIfPresent(nextOffset, forKey: .nextOffset)
      try values.encode(isComplete, forKey: .isComplete)
    }
  }

  let text: String
  let coverage: Coverage

  static func select(in record: SessionRecord, query: String, offset: Int? = nil) throws -> Self {
    try Task.checkCancellation()
    let body = capturedText(in: record)
    let count = body.count
    if let offset {
      guard (0...count).contains(offset) else { throw SelectionError.invalidOffset }
      let start = body.index(body.startIndex, offsetBy: offset)
      return passage(in: body, from: start, offset: offset, count: count)
    }
    return try bestPassage(in: body, query: query, count: count)
  }

  func prefix(_ limit: Int) -> Self {
    let excerpt = String(text.prefix(limit))
    return .init(
      text: excerpt,
      coverage: .init(
        startOffset: coverage.startOffset, endOffset: coverage.startOffset + excerpt.count,
        totalCharacters: coverage.totalCharacters))
  }

  private static func bestPassage(in body: String, query: String, count: Int) throws -> Self {
    let terms = queryTerms(query)
    var best = passage(in: body, from: body.startIndex, offset: 0, count: count)
    guard !terms.isEmpty, count > maximumCharacters else { return best }
    var bestScore = score(best.text, terms: terms)
    var offset = windowStride
    var start = body.index(body.startIndex, offsetBy: windowStride)
    while start < body.endIndex {
      try Task.checkCancellation()
      let candidate = passage(in: body, from: start, offset: offset, count: count)
      let candidateScore = score(candidate.text, terms: terms)
      if candidateScore > bestScore {
        best = candidate
        bestScore = candidateScore
      }
      guard bestScore < terms.count,
        let next = body.index(start, offsetBy: windowStride, limitedBy: body.endIndex)
      else { break }
      start = next
      offset += windowStride
    }
    return best
  }

  private static func passage(in body: String, from start: String.Index, offset: Int, count: Int)
    -> Self
  {
    let text = String(body[start...].prefix(maximumCharacters))
    return .init(
      text: text,
      coverage: .init(startOffset: offset, endOffset: offset + text.count, totalCharacters: count))
  }

  private static func score(_ text: String, terms: [String]) -> Int {
    terms.reduce(0) {
      $0 + (text.range(of: $1, options: [.caseInsensitive, .diacriticInsensitive]) == nil ? 0 : 1)
    }
  }

  private static func queryTerms(_ query: String) -> [String] {
    var seen: Set<String> = []
    var terms: [String] = []
    for word in query.split(whereSeparator: \.isWhitespace) {
      let term = String(word).folding(
        options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      if seen.insert(term).inserted { terms.append(term) }
      if terms.count == maximumQueryTerms { break }
    }
    return terms
  }

  private static func capturedText(in record: SessionRecord) -> String {
    let captured =
      ([record.transcript, record.extractedText] + record.stashedItems
      + [record.explanation]).filter { !$0.isEmpty }
    return captured.isEmpty ? record.summary : captured.joined(separator: "\n\n")
  }

  enum SelectionError: Error { case invalidOffset }
}
