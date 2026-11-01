import FoundationModels
import SilliesTextModels

extension AppleReasoningBackend: ConversationBackend {
  package func retain(for lifetime: TextModelLifetime) async {
    await conversations.retain(for: lifetime)
  }
  package var contextWindowTokens: Int { SystemLanguageModel.default.contextSize }

  package func inputTokenCount(_ request: TextGenerationRequest) async throws -> Int {
    guard #available(macOS 26.4, *) else { return try ConversationTokenEstimate.count(request) }
    let empty = try ConversationToolbox(tools: [], progress: { _ in })
    let registered = try request.tools.map { try AppleConversationTool($0, toolbox: empty) }
    var entries = Array(
      try AppleConversationTranscript.make(request, tools: registered.map { .init(tool: $0) }))
    entries.append(.prompt(.init(segments: [.text(.init(content: request.prompt))])))
    do { return try await SystemLanguageModel.default.tokenCount(for: entries) } catch {
      throw AppleGenerationFailure.recoverable(error)
    }
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
    do {
      return try await conversations.respond(request, tools: tools, receive: receive)
    } catch {
      throw AppleGenerationFailure.recoverable(error)
    }
  }
}
