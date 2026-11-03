import Foundation

/// A companion's durable identity is independent of its current name, window and voice.
public struct ConversationOwner: Equatable, Sendable {
  public let id: String
  public let name: String
  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

public struct ConversationHandle: Codable, Equatable, Sendable {
  public let companionID: String
  public let generation: UUID
  public init(companionID: String, generation: UUID) {
    self.companionID = companionID
    self.generation = generation
  }
}

/// Rebuildable context and presentation preferences; originals remain in individual message rows.
public struct ConversationCheckpoint: Codable, Equatable, Sendable {
  public var memory: ConversationMemory
  public var draft: String
  public var language: String?
  public var readingMessageID: UUID?
  public private(set) var contextRevision: UUID?
  public var memorySnapshot: ConversationMemorySnapshot {
    .init(memory: memory, revision: contextRevision)
  }
  public mutating func preserveContext(from saved: Self) {
    memory = saved.memory
    contextRevision = saved.contextRevision
  }
  public mutating func recordHistoryChange() { contextRevision = UUID() }
  public mutating func replaceMemory(_ replacement: ConversationMemory) {
    memory = replacement
    contextRevision = UUID()
  }
  public init(
    memory: ConversationMemory = .init(), draft: String = "", language: String? = nil,
    readingMessageID: UUID? = nil
  ) {
    self.memory = memory
    self.draft = draft
    self.language = language
    self.readingMessageID = readingMessageID
  }
}

public struct ConversationEntry: Identifiable, Equatable, Sendable {
  public let sequence: Int64
  public let message: ChatMessage
  public let createdAt: Date
  public var id: UUID { message.id }
  public init(sequence: Int64, message: ChatMessage, createdAt: Date) {
    self.sequence = sequence
    self.message = message
    self.createdAt = createdAt
  }
}

public struct ConversationHeader: Identifiable, Sendable {
  public let owner: ConversationOwner
  public let updatedAt: Date
  public let messageCount: Int
  public let excerpt: String
  public var id: String { owner.id }
  public init(owner: ConversationOwner, updatedAt: Date, messageCount: Int, excerpt: String) {
    self.owner = owner
    self.updatedAt = updatedAt
    self.messageCount = messageCount
    self.excerpt = excerpt
  }
}

public struct ConversationSnapshot: Sendable {
  public let handle: ConversationHandle
  public let checkpoint: ConversationCheckpoint
  public let page: ConversationPage
  public init(
    handle: ConversationHandle, checkpoint: ConversationCheckpoint, page: ConversationPage
  ) {
    self.handle = handle
    self.checkpoint = checkpoint
    self.page = page
  }
}

public struct ConversationPage: Sendable {
  public let entries: [ConversationEntry]
  public let hasOlder: Bool
  public let hasNewer: Bool
  public let isByteLimited: Bool
  public init(
    entries: [ConversationEntry], hasOlder: Bool, hasNewer: Bool, isByteLimited: Bool = false
  ) {
    self.entries = entries
    self.hasOlder = hasOlder
    self.hasNewer = hasNewer
    self.isByteLimited = isByteLimited
  }
}

public struct ConversationPageRequest: Sendable {
  public enum Position: Sendable {
    case latest
    case before(Int64)
    case beforeMessage(UUID)
    case throughMessage(UUID)
    case between(after: UUID?, before: UUID)
    case after(Int64)
    case around(UUID)
  }
  public static let defaultLimit = 60
  public static let maximumLimit = 128
  public static let maximumPageBytes = 256 * 1_024
  public let handle: ConversationHandle
  public let position: Position
  public let limit: Int
  public let maximumBytes: Int
  public init(
    handle: ConversationHandle, position: Position = .latest, limit: Int = defaultLimit,
    maximumBytes: Int = maximumPageBytes
  ) {
    self.handle = handle
    self.position = position
    self.limit = max(1, min(limit, Self.maximumLimit))
    self.maximumBytes = max(1, min(maximumBytes, Self.maximumPageBytes))
  }
}

public struct ConversationUpdate: Sendable {
  public let handle: ConversationHandle
  public let messages: [ChatMessage]
  public let removedMessageIDs: Set<UUID>
  public let checkpoint: ConversationCheckpoint
  public let savedAt: Date
  public init(
    handle: ConversationHandle, messages: [ChatMessage], checkpoint: ConversationCheckpoint,
    removedMessageIDs: Set<UUID> = [], savedAt: Date
  ) {
    self.handle = handle
    self.messages = messages
    self.checkpoint = checkpoint
    self.removedMessageIDs = removedMessageIDs
    self.savedAt = savedAt
  }
}

public struct ConversationSearchRequest: Sendable {
  public let companionID: String?
  public let query: String
  public let limit: Int
  public let excludingMessageID: UUID?
  public init(
    companionID: String? = nil, query: String, limit: Int = 20, excludingMessageID: UUID? = nil
  ) {
    self.companionID = companionID
    self.query = query
    self.limit = max(1, min(limit, ConversationPageRequest.maximumLimit))
    self.excludingMessageID = excludingMessageID
  }
}

public struct ConversationSearchMatch: Identifiable, Sendable {
  public let owner: ConversationOwner
  public let entry: ConversationEntry
  /// A query-relevant fragment of the original message. The complete entry remains available to UI.
  public let excerpt: String
  public var id: UUID { entry.id }
  public init(owner: ConversationOwner, entry: ConversationEntry, excerpt: String) {
    self.owner = owner
    self.entry = entry
    self.excerpt = excerpt
  }
}
