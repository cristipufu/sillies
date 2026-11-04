import Foundation
import MLXLMCommon
import SilliesTextModels
import Tokenizers

struct LocalTokenizerLoader: TokenizerLoader {
  let policy: TextModelPreparation.RuntimePolicy
  let timingObserver: TextPreparationTiming.Observer?
  init(
    policy: TextModelPreparation.RuntimePolicy = .standard,
    timingObserver: TextPreparationTiming.Observer? = nil
  ) {
    self.policy = policy
    self.timingObserver = timingObserver
  }
  func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
    let started = ContinuousClock.now
    let tokenizer = LocalTokenizer(
      base: try await AutoTokenizer.from(modelFolder: directory),
      template: try NativeChatTemplate.load(policy.chatTemplate))
    await timingObserver?(.init(.tokenizerSetup, since: started))
    return tokenizer
  }
}

private struct LocalTokenizer: MLXLMCommon.Tokenizer {
  let base: any Tokenizers.Tokenizer
  let template: String?
  var bosToken: String? { base.bosToken }
  var eosToken: String? { base.eosToken }
  var unknownToken: String? { base.unknownToken }
  func encode(text: String, addSpecialTokens: Bool) -> [Int] {
    base.encode(text: text, addSpecialTokens: addSpecialTokens)
  }
  func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
    base.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
  }
  func convertTokenToId(_ token: String) -> Int? { base.convertTokenToId(token) }
  func convertIdToToken(_ id: Int) -> String? { base.convertIdToToken(id) }
  func applyChatTemplate(
    messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
    additionalContext: [String: any Sendable]?
  ) throws -> [Int] {
    if let template {
      // Empty interrupted assistant placeholders have no model-authored content. The maintained
      // vendor template handles same-speaker aggregation and interrupted tool-turn ordering.
      let messages = messages.filter { message in
        guard message["role"] as? String == "assistant",
          let content = message["content"] as? String,
          content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return true }
        return !(message["tool_calls"] as? [[String: any Sendable]] ?? []).isEmpty
      }
      return try base.applyChatTemplate(
        messages: messages, chatTemplate: .literal(template), addGenerationPrompt: true,
        truncation: false, maxLength: nil, tools: tools, additionalContext: additionalContext)
    }
    return try base.applyChatTemplate(
      messages: messages, tools: tools, additionalContext: additionalContext)
  }
}
