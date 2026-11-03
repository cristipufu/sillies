import Foundation
import SilliesCore
import SilliesTextModels

package enum ConversationToolResultBudgeting: String, Codable, Sendable {
  case measured
  case providerManaged
}

/// Native roles, tool execution and context measurement are explicit backend capabilities.
package protocol ConversationBackend: ReasoningBackend, ConversationBudgeting {
  var toolResultBudgeting: ConversationToolResultBudgeting { get }
  func retain(for lifetime: TextModelLifetime) async
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) async throws -> String
  func streamConversation(
    _ request: TextGenerationRequest, tools: ConversationToolbox,
    receive: @escaping TextDeltaSink
  ) async throws -> String
}

extension ConversationBackend {
  package var toolResultBudgeting: ConversationToolResultBudgeting { .measured }
  package func retain(for lifetime: TextModelLifetime) async {}
  package func streamConversation(
    _ request: TextGenerationRequest, tools: ConversationToolbox,
    receive: @escaping TextDeltaSink
  ) async throws -> String {
    let text = try await converse(request, tools: tools)
    try await receive(text)
    return text
  }

}

/// Earlier Apple systems have no tokenizer API. The fallback deliberately overestimates typical text.
/// Exact backend limits and bounded recovery still apply to unusual tokenization.
enum ConversationTokenEstimate {
  private static let messageFramingTokens = 16
  static func count(_ request: TextGenerationRequest) throws -> Int {
    let content =
      request.instructions.utf8.count
      + request.messages.reduce(0) {
        $0 + $1.content.utf8.count + $1.calls.reduce(0) { $0 + $1.arguments.count }
      }
    return (content + (try JSONEncoder().encode(request.tools).count)) / 2
      + messageFramingTokens * (request.messages.count + 1)
  }
}
