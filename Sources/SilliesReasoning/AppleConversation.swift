import FoundationModels
import SilliesTextModels

extension AppleReasoningBackend: ConversationBackend {
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
    let registered = try request.tools.map { try AppleConversationTool($0, toolbox: tools) }
    let session = LanguageModelSession(
      model: .default, tools: registered,
      transcript: try AppleConversationTranscript.make(
        request, tools: registered.map { .init(tool: $0) }))
    do {
      var snapshot = TextStreamSnapshot()
      var batch = TextStreamBatch()
      var answer = ""
      for try await update in session.streamResponse(
        to: request.prompt, options: options(for: request))
      {
        try Task.checkCancellation()
        let delta = try snapshot.append(update.content)
        answer = update.content
        if let text = batch.append(delta) { try await receive(text) }
      }
      if let text = batch.flush() { try await receive(text) }
      return answer
    } catch {
      throw AppleGenerationFailure.recoverable(error)
    }
  }
}
