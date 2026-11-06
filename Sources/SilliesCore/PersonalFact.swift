import Foundation

/// Explicitly authored by the user. Model-written memories cannot modify this profile.
public struct PersonalFact: Codable, Equatable, Identifiable, Sendable {
  public enum Scope: String, Codable, CaseIterable, Sendable { case shared, companion }
  public static let maximumPerScope = 4
  public static let maximumValueCharacters = 200
  public let id: UUID
  public let revision: UUID
  public let scope: Scope
  public let fact: MemoryFact
  public init(id: UUID = UUID(), revision: UUID = UUID(), scope: Scope, fact: MemoryFact) {
    self.id = id
    self.revision = revision
    self.scope = scope
    self.fact = fact
  }
  public var isValid: Bool { fact.isValid && fact.value.count <= Self.maximumValueCharacters }
}

public struct PersonalFactsSnapshot: Sendable {
  public let revision: UUID
  public let facts: [PersonalFact]
  public init(revision: UUID, facts: [PersonalFact]) {
    self.revision = revision
    self.facts = facts
  }
  /// A companion-specific preference takes precedence over a shared topic.
  public var contextFacts: [PersonalFact] {
    let local = facts.filter { $0.scope == .companion }
    let localKeys = Set(local.map { $0.fact.key.lowercased() })
    return local
      + facts.filter { $0.scope == .shared && !localKeys.contains($0.fact.key.lowercased()) }
  }
}

public struct PersonalFactWrite: Sendable {
  public let handle: ConversationHandle
  public let scope: PersonalFact.Scope
  public let fact: MemoryFact
  public let replacing: PersonalFact?
  public init(
    handle: ConversationHandle, scope: PersonalFact.Scope, fact: MemoryFact,
    replacing: PersonalFact? = nil
  ) {
    self.handle = handle
    self.scope = scope
    self.fact = fact
    self.replacing = replacing
  }
}

public protocol PersonalFactsRepository: Sendable {
  func personalFacts(_ handle: ConversationHandle) async throws -> PersonalFactsSnapshot
  func savePersonalFact(_ request: PersonalFactWrite) async throws -> PersonalFactsSnapshot
  func removePersonalFact(_ fact: PersonalFact, handle: ConversationHandle) async throws
    -> PersonalFactsSnapshot
}

public enum PersonalFactError: Error, LocalizedError {
  case limit, changed, duplicate, invalid
  public var errorDescription: String? {
    switch self {
    case .limit:
      String(
        localized:
          "You can pin four shared facts and four for each companion. Edit or remove one to make room."
      )
    case .changed: String(localized: "This pinned fact changed. Reopen it before editing.")
    case .duplicate:
      String(localized: "A pinned fact already uses this topic for the selected companions.")
    case .invalid: String(localized: "Add a topic and a fact of up to 200 characters.")
    }
  }
}
