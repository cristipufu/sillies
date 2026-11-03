import Foundation
import Testing

@testable import SilliesTextModels

private let completionMetrics = TextGenerationMetrics(
  tokens: .init(processedPrompt: 1_200, cachedPrompt: 0, generated: 1),
  timing: .init(prompt: 0.2, generation: 0.01))

private func continuationRequest() -> TextGenerationRequest {
  let call = TextGenerationOutput.Call(
    id: "saved", name: "save_memory", arguments: Data("{}".utf8))
  return .init(
    conversation: .init(
      instructions: "Remember facts",
      messages: [
        .init(role: .user, content: "My name is Imani."),
        .calling([call], text: "I'll remember that."),
        .result("Memory saved.", for: call),
      ], tools: []), maximumTokens: 240, style: .conversation)
}

@Test func completedEmptyToolContinuationReachesTheConversationOwner() throws {
  let response = TextInferenceResponse(output: .init(text: "", metrics: completionMetrics))
  let output = try response.output(for: continuationRequest())
  #expect(output.text.isEmpty)
  #expect(output.metrics?.generatedTokens == 1)
}

@Test func emptyInitialResponseIsStillAnErrorAndRetainsItsNativeMeasurements() throws {
  let response = TextInferenceResponse(output: .init(text: "", metrics: completionMetrics))
  let request = TextGenerationRequest(
    instructions: "Chat", prompt: "Hello", maximumTokens: 240, style: .conversation)
  do {
    _ = try response.output(for: request)
    Issue.record("An empty initial response is not a completed conversation")
  } catch let failure as TextGenerationFailure {
    #expect(failure.reason == .emptyResponse)
    #expect(failure.metrics?.generatedTokens == 1)
  }
}

@Test func missingOrTruncatedToolCompletionCannotBecomeSuccessful() throws {
  let missing = TextInferenceResponse(output: .init(text: ""))
  #expect(throws: TextGenerationFailure.self) { try missing.output(for: continuationRequest()) }
  let failure = TextGenerationFailure(reason: .outputTokenLimit, metrics: completionMetrics)
  let truncated = TextInferenceResponse(
    failure: failure.localizedDescription, generationFailure: failure)
  do {
    _ = try truncated.output(for: continuationRequest())
    Issue.record("Truncated generation must remain a failure")
  } catch let received as TextGenerationFailure {
    #expect(received.reason == .outputTokenLimit)
  }
}
