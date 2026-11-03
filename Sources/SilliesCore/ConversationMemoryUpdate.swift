import Foundation

public struct ConversationMemorySnapshot: Equatable, Sendable {
  public let memory: ConversationMemory
  public let revision: UUID?
  public init(memory: ConversationMemory, revision: UUID?) {
    self.memory = memory
    self.revision = revision
  }
}

/// Compare-and-swap for derived memory and its source revision. Presentation never owns this write.
public struct ConversationMemoryUpdate: Sendable {
  public let handle: ConversationHandle
  public let expected: ConversationMemorySnapshot
  public let replacement: ConversationMemory

  public init(
    handle: ConversationHandle, expected: ConversationMemorySnapshot,
    replacement: ConversationMemory
  ) {
    self.handle = handle
    self.expected = expected
    self.replacement = replacement
  }
}
