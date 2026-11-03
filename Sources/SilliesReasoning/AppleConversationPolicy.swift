import SilliesCore

/// Foundation Models owns context capacity, prefill and native tool decoding. These are the
/// application's output/compaction allowances, not unsupported MLX tuning controls.
enum AppleConversationPolicy {
  static let conversation = ConversationPolicy(
    safetyTokens: 128,
    compaction: .init(summaryWords: 180, headroomTokens: 256),
    tools: .init(maximumCalls: 4, reserveTokens: 1_365, resultTokens: 768))
  static let generation = TextGenerationProfile(
    conversation: .init(
      outputTokens: 240, reasoningTokens: 0,
      sampling: .init(temperature: 0.7, topP: 0.9, topK: 0, repetitionPenalty: 1),
      repetitionContextTokens: 0),
    summary: .init(
      outputTokens: 320, reasoningTokens: 0,
      sampling: .init(temperature: 0, topP: 1, topK: 0, repetitionPenalty: 1),
      repetitionContextTokens: 0),
    precise: .init(
      outputTokens: 1_400, reasoningTokens: 0,
      sampling: .init(temperature: 0, topP: 1, topK: 0, repetitionPenalty: 1),
      repetitionContextTokens: 0))
}
