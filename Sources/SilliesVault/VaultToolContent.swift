import Foundation
import SilliesCore
import SilliesReasoning

enum VaultToolContent {
  static let maximumExcerptCharacters = VaultRecordPassage.maximumCharacters
  private static let briefExcerptCharacters = 100
  private static let maximumTitleCharacters = 120
  private static let maximumLinks = 5
  private static let maximumLinkSourceCharacters = 16_000

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
    enum Status: String, Encodable { case matches, noMatches }
    let scope = "Personal records saved by the user; not web or general-knowledge search."
    let status: Status
    let query: String
    let category: VaultSearchRequest.Category
    let coverage: String
    let returnedRecordCount: Int
    let records: [RecordPassage]
    init(_ records: [RecordPassage], request: VaultSearchRequest) {
      status = records.isEmpty ? .noMatches : .matches
      query = request.query
      category = request.category
      coverage =
        records.isEmpty
        ? "Search completed: no saved records matched this query and category."
        : "Matching record excerpts, limited to this page. returnedRecordCount counts these records, not all saved items or individual URLs. Use read_vault_record with recordID and topic keywords when the requested detail is missing from an excerpt."
      returnedRecordCount = records.count
      self.records = records
    }
  }

  private struct RecordRead: Encodable {
    struct AdditionalPassage: Encodable {
      let excerpt: String
      let coverage: VaultRecordPassage.Coverage
    }
    let record: RecordPassage
    let coverage: VaultRecordPassage.Coverage
    let guidance: String
    let additionalPassages: [AdditionalPassage]
    init(source: ChatSource, passage: VaultRecordPassage, additional: [VaultRecordPassage] = []) {
      record = RecordPassage(source, excerptLimit: passage.text.count)
      coverage = passage.coverage
      additionalPassages = additional.map { .init(excerpt: $0.text, coverage: $0.coverage) }
      guidance =
        coverage.isComplete
        ? "The complete captured text is included."
        : "This is a partial passage, not the complete record. Use nextOffset for later text, offset 0 for the beginning, or a more specific query with no offset. Do not infer that an absent detail is absent from the record."
    }
  }

  static func searchOutput(
    _ sources: [ChatSource], request: VaultSearchRequest
  ) throws
    -> ConversationToolOutput
  {
    let full = SearchPage(
      sources.map { RecordPassage($0, excerptLimit: maximumExcerptCharacters) },
      request: request)
    let brief = SearchPage(
      sources.map { RecordPassage($0, excerptLimit: briefExcerptCharacters) },
      request: request)
    return try .init(text: encoded(full), sources: sources, briefText: encoded(brief))
  }

  private static func encoded(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
  static func readOutput(_ source: ChatSource, passages: [VaultRecordPassage]) throws
    -> ConversationToolOutput
  {
    guard let passage = passages.first else {
      throw VaultRecordPassage.SelectionError.invalidOffset
    }
    return try .init(
      text: encoded(
        RecordRead(source: source, passage: passage, additional: Array(passages.dropFirst()))),
      sources: [source],
      briefText: encoded(
        RecordRead(source: source, passage: passage.prefix(briefExcerptCharacters))),
      alternatives: [encoded(RecordRead(source: source, passage: passage))])
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
}
