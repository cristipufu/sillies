import SilliesCore

/// Related history capabilities are injected together. Transient callers have no persistence owner.
package struct ConversationHistoryAccess: Sendable {
  let repository: (any ConversationRepository)?
  let tools: @Sendable (ChatContext) -> [any ConversationTool]

  package init(
    repository: (any ConversationRepository)?,
    tools: @escaping @Sendable (ChatContext) -> [any ConversationTool] = { _ in [] }
  ) {
    self.repository = repository
    self.tools = tools
  }

  package static let transient = Self(repository: nil)
}
