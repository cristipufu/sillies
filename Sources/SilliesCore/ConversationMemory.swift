import Foundation

/// A bounded working memory; it never replaces the user's full transcript.
public struct ConversationMemory: Equatable, Sendable {
  public static let maximumSummaryCharacters = 1_200
  public static let maximumOpeningCharacters = 320
  public let openingStatement: String
  public static let maximumReferences = 5
  public let summary: String
  public let throughMessageID: UUID?
  public let references: [Reference]

  public init(
    summary: String = "", throughMessageID: UUID? = nil, references: [Reference] = [],
    openingStatement: String = ""
  ) {
    self.openingStatement = String(openingStatement.prefix(Self.maximumOpeningCharacters))
    self.summary = String(summary.prefix(Self.maximumSummaryCharacters))
    self.throughMessageID = throughMessageID
    self.references = Array(references.suffix(Self.maximumReferences))
  }

  public struct Reference: Equatable, Sendable {
    private static let maximumTitleCharacters = 120
    public let id: UUID
    public let title: String
    public init(id: UUID, title: String) {
      self.id = id
      self.title = String(title.prefix(Self.maximumTitleCharacters))
    }
  }
}
