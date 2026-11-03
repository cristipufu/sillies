import SilliesCore
import SilliesTextModels

extension DownloadedReasoningBackend: ConversationBackend {
  package func retain(for lifetime: TextModelLifetime) async {
    await registry.retain(for: lifetime)
  }
  package var contextWindowTokens: Int { manifest.model.contextTokens }
  package var conversationPolicy: ConversationPolicy { manifest.model.profile.conversation }
  package var generationProfile: TextGenerationProfile { manifest.model.profile.generation }
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
      let budget = ConversationBudget(backend: self)
      guard try await budget.requiredTokens(generation) <= budget.admissionTokens else {
        throw TextModelError.contextLimit
      }
      return try await registry.stream(generation, using: manifest, receive: sink)
    }
  }
}
