import SilliesCore

/// Transient histories are explicit fixtures; production composition supplies both local stores.
package enum ChatHistoryConfiguration: Sendable {
  case transient
  case stored(conversations: any ConversationRepository, memories: any CompanionMemoryRepository)
  package var conversations: (any ConversationRepository)? {
    if case .stored(let repository, _) = self { repository } else { nil }
  }
  package var memories: (any CompanionMemoryRepository)? {
    if case .stored(_, let repository) = self { repository } else { nil }
  }
}
