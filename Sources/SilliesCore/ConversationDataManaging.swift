import Foundation

public enum ConversationDataRemoval: String, CaseIterable, Sendable {
  case messages, learnedMemories, messagesAndMemories
}

public protocol ConversationDataManaging: Sendable {
  func removeConversationData(_ removal: ConversationDataRemoval, handle: ConversationHandle)
    async throws -> ConversationSnapshot
}
