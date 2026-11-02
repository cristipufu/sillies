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
      let remainingCalls = await tools.remainingCalls
      let response = try await generate(
        roundRequest(request, messages: messages, remainingCalls: remainingCalls), round.append)
      guard remainingCalls > 0 || response.calls.isEmpty else {
        throw TextModelError.toolsUnavailable
      }
      let delivered = try await round.finalized(matching: response.text)
      if !delivered.isEmpty { portions.append(delivered) }
      if response.calls.isEmpty {
        return try ReasoningOutput.clean(portions.joined(separator: "\n"), format: .text)
      }
      if !delivered.isEmpty { try await receive("\n") }
      messages.append(
        .calling(response.calls, text: response.text, reasoningContent: response.reasoningContent))
      for call in response.calls {
        messages.append(.result(try await tools.invoke(call), for: call))
      }
    }
    throw TextModelError.invalidResponse
  }

  private static func roundRequest(
    _ request: TextGenerationRequest, messages: [TextMessage], remainingCalls: Int
  ) -> TextGenerationRequest {
    let instructions =
      remainingCalls > 0
      ? request.instructions
      : request.instructions + """


        The tool allowance for this turn is exhausted. Give the best answer supported by the conversation and the tool results already returned. State any missing evidence. No further tools are available for this turn.
        """
    return .init(
      conversation: .init(
        instructions: instructions, messages: messages,
        tools: remainingCalls > 0 ? request.tools : []),
      maximumTokens: request.maximumTokens, style: request.style
    ).inConversation(request.conversationID).inSession(request.sessionID)
  }
}
