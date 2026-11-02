import SilliesCore

/// Tasks choose an intent; native adapters translate it into their supported generation options.
package enum TextGenerationStyle: String, Codable, Sendable {
  case precise, conversation, summary

  package var temperature: Double { self == .conversation ? 0.7 : 0 }
  package var probabilityThreshold: Double { self == .conversation ? 0.9 : 1 }
  package var repetitionPenalty: Float? { self == .conversation ? 1.08 : nil }
  package var repetitionContextSize: Int { 64 }

  /// History summarization reasons over more source material than a short reply.
  /// Admission and native generation must reserve the same capacity; neither extends the deadline.
  package func reasoningTokenReserve(_ policy: TextModelReasoning?) -> Int {
    guard policy == .alwaysOnThinkTags else { return 0 }
    return self == .summary ? Self.summaryReasoningTokens : (policy?.tokenReserve ?? 0)
  }

  private static let summaryReasoningTokens = 2_048
}
