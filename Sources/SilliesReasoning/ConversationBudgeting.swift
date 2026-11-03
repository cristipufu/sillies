import SilliesCore
import SilliesTextModels

/// Foreground preparation can measure requests but has no generation capability.
package protocol ConversationBudgeting: Sendable {
  var contextWindowTokens: Int { get }
  var conversationPolicy: ConversationPolicy { get }
  var generationProfile: TextGenerationProfile { get }
  func inputTokenCount(_ request: TextGenerationRequest) async throws -> Int
}

extension ConversationBudgeting {
  package var reasoningTokenReserve: Int { generationProfile.conversation.reasoningTokens }
  package func reasoningTokenReserve(for style: TextGenerationStyle) -> Int {
    style.settings(in: generationProfile).reasoningTokens
  }
}
