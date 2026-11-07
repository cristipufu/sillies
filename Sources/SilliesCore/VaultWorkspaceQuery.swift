import Foundation

/// The same query describes an interactive search, a saved search, and a batch selection.
public struct VaultWorkspaceQuery: Codable, Hashable, Sendable {
  public enum Scope: String, Codable, CaseIterable, Sendable {
    case all, starred, notes, meetings, screenshots, links, conversations, trash
  }
  public enum Ordering: String, Codable, CaseIterable, Sendable {
    case newest, oldest, modified, relevance
  }
  public enum Content: String, Codable, Sendable { case savedURLs }
  public var content: Content?
  public var scope: Scope
  public var text: String
  public var textMatching: VaultTextMatching?
  public var ordering: Ordering
  public var collectionID: UUID?
  public var tag: String?
  public var kind: CompanionSkillKind?
  public var source: VaultSourceFilter?
  public var from: Date?
  public var until: Date?
  public var searchesAllActiveItems: Bool {
    scope == .all && collectionID == nil && tag == nil && kind == nil && from == nil && until == nil
      && content == nil && source?.isEmpty != false
  }

  public init(scope: Scope = .all, text: String = "", ordering: Ordering = .newest) {
    self.scope = scope
    self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    self.ordering = ordering
  }
}
