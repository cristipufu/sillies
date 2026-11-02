import Foundation
import SilliesTextModels

/// Native roles, tool execution and context measurement are explicit backend capabilities.
package protocol ConversationBackend: ReasoningBackend {
  var contextWindowTokens: Int { get }
  var reasoningTokenReserve: Int { get }
  func retain(for lifetime: TextModelLifetime) async
  func inputTokenCount(_ request: TextGenerationRequest) async throws -> Int
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) async throws -> String
  func streamConversation(
    _ request: TextGenerationRequest, tools: ConversationToolbox,
    receive: @escaping TextDeltaSink
  ) async throws -> String
}

extension ConversationBackend {
  package func retain(for lifetime: TextModelLifetime) async {}
  package func streamConversation(
    _ request: TextGenerationRequest, tools: ConversationToolbox,
    receive: @escaping TextDeltaSink
  ) async throws -> String {
    let text = try await converse(request, tools: tools)
    try await receive(text)
    return text
  }
  package var contextWindowTokens: Int { 4_096 }
  package func inputTokenCount(_ request: TextGenerationRequest) async throws -> Int {
    try ConversationTokenEstimate.count(request)
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
