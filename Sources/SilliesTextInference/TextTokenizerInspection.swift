import Foundation
import SilliesTextModels

/// Explicit diagnostic for synthetic requests using the standard chat message generator.
/// Does not load model weights, run inference, or include any generated reasoning.
enum TextTokenizerInspection {
  private struct Inspection: Encodable {
    let tokenCount: Int
    let renderedPrompt: String
  }

  static func run(requestURL: URL) async throws {
    let request = try TextInferenceJSON.read(
      TextInferenceRequest.self, from: requestURL,
      maximumBytes: TextInferenceWire.maximumMessageBytes)
    let tokenizer = try await LocalTokenizerLoader(
      policy: request.configuration.profile.runtimePolicy
    )
    .load(from: request.configuration.directory)
    let tokens = try tokenizer.applyChatTemplate(
      messages: MLXConversationInput.templateMessages(request.generation),
      tools: request.generation.tools.isEmpty
        ? nil : MLXConversationInput.tools(request.generation),
      additionalContext: MLXReasoningPolicy(reasoning: request.configuration.reasoning)
        .templateContext)
    let inspection = Inspection(
      tokenCount: tokens.count, renderedPrompt: tokenizer.decode(tokenIds: tokens))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    print(String(decoding: try encoder.encode(inspection), as: UTF8.self))
  }
}
