import Foundation

/// A user-visible fact with original-message provenance; separate from lossy context summaries.
public struct MemoryFact: Codable, Equatable, Sendable {
  public let key: String
  public let value: String
  public init(key: String, value: String) {
    self.key = key
    self.value = value
  }
}

public struct MemorySource: Codable, Equatable, Sendable {
  public let messageID: UUID
  public let quote: String
  public init(messageID: UUID, quote: String) {
    self.messageID = messageID
    self.quote = quote
  }
}

public struct CompanionMemory: Codable, Equatable, Identifiable, Sendable {
  public struct Reference: Equatable, Sendable {
    public let id: UUID
    public let revision: UUID
    public init(id: UUID, revision: UUID) {
      self.id = id
      self.revision = revision
    }
  }
  public let id: UUID
  public let revision: UUID
  public let fact: MemoryFact
  public let source: MemorySource
  public let savedAt: Date
  public var key: String { fact.key }
  public var value: String { fact.value }
  public var sourceMessageID: UUID { source.messageID }
  public var sourceQuote: String { source.quote }
  public var reference: Reference { .init(id: id, revision: revision) }
  public init(
    replacing previous: CompanionMemory?, fact: MemoryFact, source: MemorySource, savedAt: Date
  ) {
    id = previous?.id ?? UUID()
    revision = UUID()
    self.fact = fact
    self.source = source
    self.savedAt = savedAt
  }
}

public struct MemoryWrite: Sendable {
  public let handle: ConversationHandle
  public let fact: MemoryFact
  public let source: MemorySource
  public let savedAt: Date
  public private(set) var replacement: CompanionMemory.Reference?
  public var key: String { fact.key }
  public var value: String { fact.value }
  public var sourceMessageID: UUID { source.messageID }
  public var sourceQuote: String { source.quote }
  public init(handle: ConversationHandle, fact: MemoryFact, source: MemorySource, savedAt: Date) {
    self.handle = handle
    self.fact = fact
    self.source = source
    self.savedAt = savedAt
  }

  public func replacing(_ reference: CompanionMemory.Reference) -> Self {
    var copy = self
    copy.replacement = reference
    return copy
  }
}

public enum MemoryMutationError: Error { case replacementChanged }

public struct MemoryReceipt: Codable, Equatable, Identifiable, Sendable {
  public let handle: ConversationHandle
  public let id: UUID
  public let previous: CompanionMemory?
  public let saved: CompanionMemory
  public init(
    handle: ConversationHandle, id: UUID, previous: CompanionMemory?, saved: CompanionMemory
  ) {
    self.handle = handle
    self.id = id
    self.previous = previous
    self.saved = saved
  }
}

public protocol CompanionMemoryRepository: Sendable {
  func memories(_ handle: ConversationHandle, query: String) async throws -> [CompanionMemory]
  func remember(_ request: MemoryWrite) async throws -> MemoryReceipt
  func forget(_ handle: ConversationHandle, id: UUID) async throws -> ConversationSnapshot
  func undoMemory(_ handle: ConversationHandle, receiptID: UUID) async throws
    -> ConversationSnapshot
  func recentMemoryChanges(_ handle: ConversationHandle) async throws -> [MemoryReceipt]
}
