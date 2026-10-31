import Foundation

public struct SessionRecordSearch: Sendable {
  public let kind: CompanionSkillKind?
  public let query: String

  public init(kind: CompanionSkillKind?, query: String) {
    self.kind = kind
    self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func matches(_ record: SessionRecord) -> Bool {
    if let kind, record.kind != kind { return false }
    guard !query.isEmpty else { return true }
    return matchesText(record.displayTitle) || matchesText(record.summary)
      || matchesText(record.transcript) || matchesText(record.extractedText)
      || record.stashedItems.contains(where: matchesText)
  }

  private func matchesText(_ text: String) -> Bool {
    !text.isEmpty
      && text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
  }
}
