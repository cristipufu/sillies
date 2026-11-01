import FoundationModels
import SilliesTextModels

protocol AppleChatSession: Sendable {
  func respond(_ request: TextGenerationRequest, receive: @escaping TextDeltaSink) async throws
    -> String
}

struct NativeAppleChatSession: AppleChatSession {
  private let session: LanguageModelSession

  init(request: TextGenerationRequest, invocation: AppleToolInvocation) throws {
    let registered = try request.tools.map {
      try AppleConversationTool($0, invoke: invocation.invoke)
    }
    session = LanguageModelSession(
      model: .default, tools: registered,
      transcript: try AppleConversationTranscript.make(
        request, tools: registered.map { .init(tool: $0) }))
  }

  func respond(_ request: TextGenerationRequest, receive: @escaping TextDeltaSink) async throws
    -> String
  {
    var snapshot = TextStreamSnapshot()
    var batch = TextStreamBatch()
    var answer = ""
    for try await update in session.streamResponse(
      to: request.prompt, options: AppleGenerationOptions.make(request))
    {
      try Task.checkCancellation()
      let delta = try snapshot.append(update.content)
      answer = update.content
      if let text = batch.append(delta) { try await receive(text) }
    }
    if let text = batch.flush() { try await receive(text) }
    try Task.checkCancellation()
    return answer
  }
}
