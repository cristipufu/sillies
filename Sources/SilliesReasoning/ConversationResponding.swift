import SilliesCore
import SilliesTextModels

package typealias ConversationTextSink = @Sendable (String) async throws -> Void

/// Chat has no knowledge of a model registry, prompts, or a concrete reasoning backend.
package protocol ConversationResponding: Sendable {
  func retain(for lifetime: TextModelLifetime) async
  func availabilityNotice(localeIdentifier: String?) async -> String?
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  func streamReply(
    to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void,
    receive: @escaping ConversationTextSink
  ) async throws -> ChatReply
}

extension ConversationResponding {
  package func retain(for lifetime: TextModelLifetime) async {}
  package func streamReply(
    to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void,
    receive: @escaping ConversationTextSink
  ) async throws -> ChatReply {
    let reply = try await reply(to: context, progress: progress)
    try await receive(reply.text)
    return reply
  }
  package func availabilityNotice(localeIdentifier: String?) async -> String? { nil }
  package func reply(to context: ChatContext) async throws -> ChatReply {
    try await reply(to: context, progress: { _ in })
  }
}
