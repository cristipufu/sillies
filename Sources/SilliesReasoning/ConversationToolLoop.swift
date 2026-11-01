import SilliesTextModels

enum ConversationToolLoop {
  static func run(
    _ request: TextGenerationRequest, tools: ConversationToolbox,
    receive: @escaping TextDeltaSink = { _ in },
    generate:
      @Sendable (TextGenerationRequest, @escaping TextDeltaSink) async throws ->
      TextGenerationOutput
  ) async throws -> String {
    var messages = request.messages
    var portions: [String] = []
    for _ in 0...ConversationToolbox.maximumCalls {
      try Task.checkCancellation()
      let round = ConversationStreamDelivery(receive: receive)
      let response = try await generate(
        .init(
          conversation: .init(
            instructions: request.instructions, messages: messages, tools: request.tools),
          maximumTokens: request.maximumTokens, style: request.style
        ).inConversation(request.conversationID).inSession(request.sessionID), round.append)
      let delivered = try await round.finalized(matching: response.text)
      if !delivered.isEmpty { portions.append(delivered) }
      if response.calls.isEmpty {
        return try ReasoningOutput.clean(portions.joined(separator: "\n"), format: .text)
      }
      if !delivered.isEmpty { try await receive("\n") }
      messages.append(.calling(response.calls, text: response.text))
      for call in response.calls {
        messages.append(.result(try await tools.invoke(call), for: call))
      }
    }
    throw TextModelError.invalidResponse
  }
}
