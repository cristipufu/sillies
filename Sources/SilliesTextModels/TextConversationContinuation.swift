import Foundation
import SilliesCore

/// Reuse requires the exact committed conversation, including roles, tools and session identity.
package struct TextConversationContinuation: Sendable {
  private let sessionID: UUID?
  private let instructions: String
  private let tools: [ConversationToolDefinition]
  private let messages: [TextMessage]

  package init(
    request: TextGenerationRequest, response: TextGenerationOutput,
    completedExchanges: [ConversationToolExchange] = []
  ) {
    sessionID = request.sessionID
    instructions = request.instructions
    tools = request.tools
    messages =
      request.messages + TextMessage.exchanging(completedExchanges)
      + [.calling(response.calls, text: response.text, reasoningContent: response.reasoningContent)]
  }

  package func suffix(for request: TextGenerationRequest) -> [TextMessage]? {
    guard let sessionID, request.sessionID == sessionID,
      request.instructions == instructions, request.tools == tools,
      request.messages.count > messages.count, request.messages.starts(with: messages)
    else { return nil }
    return Array(request.messages.dropFirst(messages.count))
  }
}
