import Foundation
import SilliesCore

/// Each invocation is scoped to one companion and the current user statement by composition.
package struct ConversationHistoryTools: Sendable {
  package let conversations: any ConversationRepository
  package let memories: any CompanionMemoryRepository

  package init(conversations: any ConversationRepository, memories: any CompanionMemoryRepository) {
    self.conversations = conversations
    self.memories = memories
  }

  package func tools(for context: ChatContext) -> [any ConversationTool] {
    guard let handle = context.historyHandle, let statement = context.messages.last,
      statement.role == .user
    else { return [] }
    return [
      ConversationSearchTool(
        repository: conversations, handle: handle, currentMessageID: statement.id),
      MemorySearchTool(repository: memories, handle: handle, companionName: context.companionName),
      MemorySaveTool(repository: memories, handle: handle, statement: statement),
    ]
  }
}
