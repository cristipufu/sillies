import Foundation
import SilliesCore

/// Selects bounded evidence without letting an early, broad keyword hide a later relevant passage.
struct VaultRecordPassage {
  static let maximumCharacters = 1_600
  private static let maximumPassages = 3
  private struct Cursor {
    let index: String.Index
    let offset: Int
  }
  struct Source {
    let text: String
    let title: String
    struct Section {
      let kind: VaultDocumentSection
      let text: String
      let characters: Range<Int>
    }
    let sections: [Section]
    init(sections: [(VaultDocumentSection, String)], title: String) {
      var text = ""
      var locations: [Section] = []
      for (kind, value) in sections where !value.isEmpty {
        if !text.isEmpty { text += "\n\n" }
        let start = text.count
        text += value
        locations.append(.init(kind: kind, text: value, characters: start..<text.count))
      }
      self.text = text
      self.title = title
      self.sections = locations
    }
    init(record: SessionRecord, notes: String = "", title: String? = nil) {
      let captured =
        ([record.transcript, record.extractedText] + record.stashedItems + [record.explanation])
        .filter { !$0.isEmpty }
      let sourceText = captured.isEmpty ? record.summary : captured.joined(separator: "\n\n")
      text = [sourceText, notes].filter { !$0.isEmpty }.joined(separator: "\n\n")
      self.title = title ?? record.windowTitle ?? record.appName
      sections = []
    }
  }

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

  func evidence(
    in source: Source,
    read: (VaultDocumentSection, Range<Int>, String) throws -> [VaultEvidencePassage]
  )
    rethrows -> [VaultEvidencePassage]
  {
    let selected = coverage.startOffset..<coverage.endOffset
    return try source.sections.flatMap { section -> [VaultEvidencePassage] in
      let overlap = selected.clamped(to: section.characters)
      guard !overlap.isEmpty else { return [] }
      let start = section.text.index(
        section.text.startIndex, offsetBy: overlap.lowerBound - section.characters.lowerBound)
      let end = section.text.index(start, offsetBy: overlap.count)
      let offset = section.text.utf8.distance(from: section.text.startIndex, to: start)
      let text = String(section.text[start..<end])
      return try read(section.kind, offset..<(offset + text.utf8.count), text)
    }
  }

  static func selectRelated(in record: SessionRecord, query: String, offset: Int? = nil) throws
    -> [Self]
  {
    try selectRelated(in: Source(record: record), query: query, offset: offset)
  }

  static func selectRelated(in source: Source, query: String, offset: Int? = nil) throws -> [Self] {
    let first = try select(in: source, query: query, offset: offset)
    guard offset == nil else { return [first] }
    let body = source.text
    let terms = VaultPassageQuery(query: query, title: source.title)
    var selected = [first]
    while selected.count < maximumPassages {
      try Task.checkCancellation()
      let missing = terms.missingDetails(in: selected.map(\.text))
      guard !missing.isEmpty else { break }
      let remaining = VaultPassageQuery(query: missing.sorted().joined(separator: " "), title: "")
      let next = try bestPassage(in: body, query: remaining, count: body.count)
      guard remaining.score(next.text).details > 0,
        !selected.contains(where: { $0.coverage.startOffset == next.coverage.startOffset })
      else { break }
      selected.append(next)
    }
    return selected
  }

  static func select(
    in record: SessionRecord, query: String, offset: Int? = nil,
    maximumCharacters: Int = Self.maximumCharacters
  ) throws -> Self {
    try select(
      in: Source(record: record), query: query, offset: offset, maximumCharacters: maximumCharacters
    )
  }

  static func select(
    in source: Source, query: String, offset: Int? = nil,
    maximumCharacters: Int = Self.maximumCharacters
  ) throws -> Self {
    try Task.checkCancellation()
    let limit = min(Self.maximumCharacters, max(1, maximumCharacters))
    let body = source.text
    let count = body.count
    if let offset {
      guard (0...count).contains(offset) else { throw SelectionError.invalidOffset }
      let start = body.index(body.startIndex, offsetBy: offset)
      return passage(
        in: body, from: .init(index: start, offset: offset), count: count, limit: limit)
    }
    let query = VaultPassageQuery(query: query, title: source.title)
    return try bestPassage(in: body, query: query, count: count, limit: limit)
  }

  func prefix(_ limit: Int) -> Self {
    let excerpt = String(text.prefix(limit))
    return .init(
      text: excerpt,
      coverage: .init(
        startOffset: coverage.startOffset, endOffset: coverage.startOffset + excerpt.count,
        totalCharacters: coverage.totalCharacters))
  }

  private static func bestPassage(
    in body: String, query: VaultPassageQuery, count: Int, limit: Int = maximumCharacters
  ) throws
    -> Self
  {
    var best = passage(
      in: body, from: .init(index: body.startIndex, offset: 0), count: count, limit: limit)
    guard !query.all.isEmpty, count > limit else { return best }
    let windowStride = max(1, limit / 2)
    var bestScore = query.score(best.text)
    var offset = windowStride
    var start = body.index(body.startIndex, offsetBy: windowStride)
    while start < body.endIndex {
      try Task.checkCancellation()
      let candidate = passage(
        in: body, from: .init(index: start, offset: offset), count: count, limit: limit)
      let candidateScore = query.score(candidate.text)
      if candidateScore > bestScore {
        best = candidate
        bestScore = candidateScore
      }
      guard bestScore.total < query.all.count,
        let next = body.index(start, offsetBy: windowStride, limitedBy: body.endIndex)
      else { break }
      start = next
      offset += windowStride
    }
    return best
  }

  private static func passage(
    in body: String, from cursor: Cursor, count: Int, limit: Int
  )
    -> Self
  {
    let text = String(body[cursor.index...].prefix(limit))
    return .init(
      text: text,
      coverage: .init(
        startOffset: cursor.offset, endOffset: cursor.offset + text.count, totalCharacters: count))
  }

  enum SelectionError: Error { case invalidOffset }
}
