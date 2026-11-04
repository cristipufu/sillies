import MLXLLM
import MLXLMCommon
import SilliesTextModels

enum MLXPrefixBoundary {
  /// Compare two native renders instead of guessing delimiters or slicing a serialized message.
  static func count(tokens: [Int], plan: MLXGenerationPlan, context: ModelContext) async throws
    -> Int
  {
    let generator =
      context.configuration.messageGenerator
      ?? (context.model as? any LLMModel)?.messageGenerator(tokenizer: context.tokenizer)
      ?? DefaultMessageGenerator()
    var messages = try MLXConversationInput.templateMessages(
      plan.request.generation, generator: generator)
    guard let lastUser = messages.lastIndex(where: { $0["role"] as? String == "user" }) else {
      return 0
    }
    messages[lastUser]["content"] = ""
    let boundary = try await context.processor.prepare(
      input: UserInput(
        messages: messages, tools: plan.tools,
        additionalContext: plan.templateContext))
    return zip(tokens, boundary.text.tokens.asArray(Int.self)).prefix { $0 == $1 }.count
  }
}
