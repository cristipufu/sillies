import SilliesCore

package struct TextGenerationOutput: Codable, Sendable {
  package typealias Call = ConversationToolCall
  package let inputTokens: Int?
  package let text: String
  package let calls: [ConversationToolCall]
  package let metrics: TextGenerationMetrics?
  package init(
    text: String, calls: [ConversationToolCall] = [], inputTokens: Int? = nil,
    metrics: TextGenerationMetrics? = nil
  ) {
    self.inputTokens = inputTokens
    self.text = text
    self.calls = calls
    self.metrics = metrics
  }
}
