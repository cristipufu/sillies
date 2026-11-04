import Foundation

/// Search and browsing bound decoded facts independently of the number stored on disk.
public struct CompanionMemoryQuery: Sendable {
  public static let maximumResults = 200
  public let handle: ConversationHandle
  public let text: String
  public let limit: Int

  public init(handle: ConversationHandle, text: String, limit: Int = 4) {
    self.handle = handle
    self.text = text
    self.limit = min(Self.maximumResults, max(1, limit))
  }
}

public struct CompanionMemoryCursor: Equatable, Sendable {
  public let savedAt: Date
  public let id: UUID

  public init(_ memory: CompanionMemory) {
    savedAt = memory.savedAt
    id = memory.id
  }
}

public struct CompanionMemoryPageRequest: Sendable {
  public enum Position: Equatable, Sendable {
    case latest
    case before(CompanionMemoryCursor)
    case after(CompanionMemoryCursor)
  }
  public static let pageSize = 40
  public let handle: ConversationHandle
  public let position: Position

  public init(handle: ConversationHandle, position: Position = .latest) {
    self.handle = handle
    self.position = position
  }
}

public struct CompanionMemoryPage: Sendable {
  public let facts: [CompanionMemory]
  public let next: CompanionMemoryCursor?
  public let previous: CompanionMemoryCursor?

  public init(
    facts: [CompanionMemory], next: CompanionMemoryCursor?, previous: CompanionMemoryCursor? = nil
  ) {
    self.facts = facts
    self.next = next
    self.previous = previous
  }
}
