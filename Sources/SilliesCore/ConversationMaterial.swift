import Foundation

/// Explicit references, never copies of a record body. The latest saved material is read per turn.
public struct ConversationRecordSelection: Codable, Equatable, Sendable {
  public static let maximumRecords = 3
  public private(set) var ids: [UUID]
  public init() { ids = [] }
  public mutating func add(_ id: UUID) throws {
    guard !ids.contains(id) else { return }
    guard ids.count < Self.maximumRecords else { throw ConversationMaterialError.selectionFull }
    ids.append(id)
  }
  public mutating func remove(_ id: UUID) { ids.removeAll { $0 == id } }
  private enum CodingKeys: CodingKey { case ids }
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    ids = try container.decode([UUID].self, forKey: .ids)
    guard ids.count <= Self.maximumRecords, Set(ids).count == ids.count else {
      throw ConversationStorageError.invalidData
    }
  }
}

public struct ConversationRecordContext: Equatable, Sendable, Identifiable {
  public static let maximumExcerptCharacters = 480
  public static let maximumTitleCharacters = 120
  public let id: UUID
  public let title: String
  public let source: ChatSource?
  public let isComplete: Bool
  public var isAvailable: Bool { source != nil }
  public init(id: UUID, title: String, source: ChatSource?, isComplete: Bool) {
    self.id = id
    self.title = String(title.prefix(Self.maximumTitleCharacters))
    self.source = source
    self.isComplete = isComplete
  }
}

public protocol ConversationMaterialProviding: Sendable {
  func selectedRecords(_ selection: ConversationRecordSelection, query: String) async throws
    -> [ConversationRecordContext]
}

public struct ConversationBackground: Sendable {
  public let records: [ConversationRecordContext]
  public let personalFacts: PersonalFactsSnapshot?
  public let omittedPersonalFacts: Int
  public init(
    records: [ConversationRecordContext] = [], personalFacts: PersonalFactsSnapshot? = nil,
    omittedPersonalFacts: Int = 0
  ) {
    self.records = records
    self.personalFacts = personalFacts
    self.omittedPersonalFacts = omittedPersonalFacts
  }
  public func referencingRecords() -> Self {
    .init(
      records: records.map {
        .init(id: $0.id, title: $0.title, source: $0.source?.withExcerpt(""), isComplete: false)
      }, personalFacts: personalFacts, omittedPersonalFacts: omittedPersonalFacts)
  }
  public func omittingLastFact() -> Self {
    guard let personalFacts, !personalFacts.contextFacts.isEmpty else { return self }
    return .init(
      records: records,
      personalFacts: .init(
        revision: personalFacts.revision, facts: Array(personalFacts.contextFacts.dropLast())),
      omittedPersonalFacts: omittedPersonalFacts + 1)
  }
}

public enum ConversationMaterialError: Error, LocalizedError {
  case selectionFull
  public var errorDescription: String? {
    String(localized: "Choose up to three Vault items. Remove one before adding another.")
  }
}
