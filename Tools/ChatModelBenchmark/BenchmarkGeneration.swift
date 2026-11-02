import Foundation
import SilliesTextModels

/// Synthetic prompt and outcome evidence; private reasoning stays in the runtime.
struct BenchmarkGeneration: Encodable, Sendable {
  let request: TextGenerationRequest
  let inputReasoningBytes: Int
  let output: TextGenerationOutput?
  let outputReasoningBytes: Int
  let failure: TextGenerationFailure?
  let error: String?
  let seconds: Double

  init(
    request: TextGenerationRequest, outcome: Result<TextGenerationOutput, any Error>,
    seconds: Double
  ) {
    inputReasoningBytes = request.messages.reduce(0) { $0 + ($1.reasoningContent?.utf8.count ?? 0) }
    let messages = request.messages.map { message in
      var copy = message
      copy.reasoningContent = nil
      return copy
    }
    self.request = TextGenerationRequest(
      conversation: .init(
        instructions: request.instructions, messages: messages, tools: request.tools),
      maximumTokens: request.maximumTokens, style: request.style
    ).inConversation(request.conversationID).inSession(request.sessionID)
    self.seconds = seconds
    switch outcome {
    case .success(let result):
      outputReasoningBytes = result.reasoningContent?.utf8.count ?? 0
      output = .init(
        text: result.text, calls: result.calls, inputTokens: result.inputTokens,
        metrics: result.metrics)
      failure = nil
      error = nil
    case .failure(let caught):
      outputReasoningBytes = 0
      output = nil
      failure = caught as? TextGenerationFailure
      error = String(describing: caught)
    }
  }
}
