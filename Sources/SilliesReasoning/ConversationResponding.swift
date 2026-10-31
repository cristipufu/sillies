import SilliesCore

/// Chat has no knowledge of a model registry, prompts, or a concrete reasoning backend.
package protocol ConversationResponding: Sendable {
  func availabilityNotice(localeIdentifier: String?) async -> String?
  func reply(to context: ChatContext) async throws -> String
}

extension ConversationResponding {
  package func availabilityNotice(localeIdentifier: String?) async -> String? { nil }
}
