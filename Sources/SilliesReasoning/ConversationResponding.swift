import SilliesCore

/// Chat has no knowledge of a model registry, prompts, or a concrete reasoning backend.
package protocol ConversationResponding: Sendable {
  func reply(to context: ChatContext) async throws -> String
}
