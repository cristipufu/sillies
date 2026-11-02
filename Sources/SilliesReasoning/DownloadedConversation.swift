import SilliesTextModels

extension DownloadedReasoningBackend: ConversationBackend {
  package func retain(for lifetime: TextModelLifetime) async {
    await registry.retain(for: lifetime)
  }
  package var contextWindowTokens: Int { manifest.model.contextTokens }
  package var reasoningTokenReserve: Int { manifest.model.reasoning?.tokenReserve ?? 0 }
  package func inputTokenCount(_ request: TextGenerationRequest) async throws -> Int {
    let output = try await registry.complete(request.measuringTokens(), using: manifest)
    guard let count = output.inputTokens, count >= 0 else { throw TextModelError.invalidResponse }
    return count
  }
  package func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) async throws
    -> String
  {
    try await streamConversation(request, tools: tools, receive: { _ in })
  }
  package func streamConversation(
    _ request: TextGenerationRequest, tools: ConversationToolbox,
    receive: @escaping TextDeltaSink
  ) async throws -> String {
    try await ConversationToolLoop.run(request, tools: tools, receive: receive) {
      generation, sink in
      try await registry.stream(generation, using: manifest, receive: sink)
    }
  }
}
