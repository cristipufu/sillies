import SilliesReasoning
import SilliesTextModels

struct MeasuredConversationBackend: ConversationBackend {
  let base: any ConversationBackend
  let trace: BenchmarkTurnTrace
  var contextWindowTokens: Int { base.contextWindowTokens }
  func availabilityNotice(localeIdentifier: String?) async -> String? {
    await base.availabilityNotice(localeIdentifier: localeIdentifier)
  }
  func retain(for lifetime: TextModelLifetime) async { await base.retain(for: lifetime) }
  func inputTokenCount(_ request: TextGenerationRequest) async throws -> Int {
    let count = try await base.inputTokenCount(request)
    await trace.counted(count)
    return count
  }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> String {
    await trace.summarized(request)
    return try await base.generate(request, format: format)
  }
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) async throws -> String
  {
    try await streamConversation(request, tools: tools, receive: { _ in })
  }
  func streamConversation(
    _ request: TextGenerationRequest, tools: ConversationToolbox, receive: @escaping TextDeltaSink
  ) async throws -> String {
    await trace.requested(request)
    return try await base.streamConversation(request, tools: tools, receive: receive)
  }
}
