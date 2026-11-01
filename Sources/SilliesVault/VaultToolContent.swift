import Foundation
import SilliesCore
import SilliesReasoning

enum VaultToolContent {
  static let maximumExcerptCharacters = 1_600
  private static let briefExcerptCharacters = 100
  private static let maximumTitleCharacters = 120
  private static let maximumLinks = 5
  private static let maximumLinkSourceCharacters = 16_000
  private static let maximumQueryTerms = 8
  private static let leadingContextCharacters = 160

  private struct RecordPassage: Encodable {
    let recordID: UUID
    let hasImage: Bool
    let displayedInChat = true
    let title: String
    let kind: String
    let excerpt: String
    let links: [URL]
    init(_ source: ChatSource, excerptLimit: Int) {
      recordID = source.id
      hasImage = source.imageFilename != nil
      title = String(source.title.prefix(maximumTitleCharacters))
      kind = source.kind.rawValue
      excerpt = String(source.excerpt.prefix(excerptLimit))
      links = source.links
    }
  }

  private struct SearchPage: Encodable {
    let scope = "Personal records saved by the user; not web or general-knowledge search."
    let totalVaultRecords: Int
    let returnedRecordCount: Int
    let records: [RecordPassage]
    init(_ records: [RecordPassage], totalVaultRecords: Int) {
      self.totalVaultRecords = totalVaultRecords
      returnedRecordCount = records.count
      self.records = records
    }
  }

  static func searchOutput(_ sources: [ChatSource], totalVaultRecords: Int) throws
    -> ConversationToolOutput
  {
    let full = SearchPage(
      sources.map { RecordPassage($0, excerptLimit: maximumExcerptCharacters) },
      totalVaultRecords: totalVaultRecords)
    let brief = SearchPage(
      sources.map { RecordPassage($0, excerptLimit: briefExcerptCharacters) },
      totalVaultRecords: totalVaultRecords)
    return try .init(text: encoded(full), sources: sources, briefText: encoded(brief))
  }

  private static func encoded(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
  static func output(_ sources: [ChatSource]) throws -> ConversationToolOutput {
    let full = try encoded(
      sources.map { RecordPassage($0, excerptLimit: maximumExcerptCharacters) })
    let brief = try encoded(
      sources.map { RecordPassage($0, excerptLimit: briefExcerptCharacters) })
    return .init(
      text: full, sources: sources, briefText: brief)
  }
  static func links(in record: SessionRecord) throws -> [URL] {
    let text = String(
      record.stashedItems.joined(separator: "\n").prefix(maximumLinkSourceCharacters))
    let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    var result: [URL] = []
    detector.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) {
      match, _, stop in
      guard let url = match?.url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
        !result.contains(url)
      else { return }
      result.append(url)
      if result.count >= maximumLinks { stop.pointee = true }
    }
    return result
  }
  static func excerpt(in record: SessionRecord, query: String) -> String {
    let candidates = [record.transcript, record.extractedText, record.summary, record.explanation]
    let terms = query.split(whereSeparator: \.isWhitespace).prefix(maximumQueryTerms)
    for candidate in candidates where !candidate.isEmpty {
      for term in terms {
        if let range = candidate.range(
          of: String(term), options: [.caseInsensitive, .diacriticInsensitive])
        {
          let start =
            candidate.index(
              range.lowerBound, offsetBy: -leadingContextCharacters, limitedBy: candidate.startIndex
            ) ?? candidate.startIndex
          return String(candidate[start...].prefix(maximumExcerptCharacters))
        }
      }
    }
    return String(record.primaryText.prefix(maximumExcerptCharacters))
  }
}
