import SilliesCore

/// Related history capabilities are injected together. Transient callers have no persistence owner.
package struct ConversationHistoryAccess: Sendable {
  let repository: (any ConversationRepository)?
  let tools: @Sendable (ChatContext) -> [any ConversationTool]
  let background: ConversationBackgroundAccess

  package init(
    repository: (any ConversationRepository)?,
    tools: @escaping @Sendable (ChatContext) -> [any ConversationTool] = { _ in [] },
    background: ConversationBackgroundAccess = .empty
  ) {
    self.repository = repository
    self.tools = tools
    self.background = background
  }

  package static let transient = Self(repository: nil)
}
