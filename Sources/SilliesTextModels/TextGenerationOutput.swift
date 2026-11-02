import SilliesCore

package struct TextGenerationOutput: Codable, Sendable {
  package typealias Call = ConversationToolCall
  package let inputTokens: Int?
  package let text: String
  package let calls: [ConversationToolCall]
  package let metrics: TextGenerationMetrics?
  /// Ephemeral provider state for continuing this tool turn, never a displayed or saved reply.
  package let reasoningContent: String?
  package init(
    text: String, calls: [ConversationToolCall] = [], inputTokens: Int? = nil,
    metrics: TextGenerationMetrics? = nil, reasoningContent: String? = nil
  ) {
    self.inputTokens = inputTokens
    self.text = text
    self.calls = calls
    self.metrics = metrics
    self.reasoningContent = reasoningContent
  }
}
