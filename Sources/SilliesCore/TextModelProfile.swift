import Foundation

/// Reviewed settings for one checkpoint/runtime combination. Algorithms consume capabilities,
/// never model names. Published capacity and the application's working set are deliberately distinct.
public struct TextModelProfile: Codable, Equatable, Sendable {
  public struct Context: Codable, Equatable, Sendable {
    public let maximumTokens: Int
    public let workingTokens: Int
    public var isValid: Bool {
      workingTokens > 0 && workingTokens <= maximumTokens
    }
  }

  public struct Prefill: Codable, Equatable, Sendable {
    /// nil preserves the runtime's model-selected chunk size, including model-specific ceilings.
    public let chunkTokens: Int?
    public var isValid: Bool { chunkTokens.map { $0 > 0 } ?? true }
  }

  public struct Evidence: Codable, Equatable, Sendable {
    public let sources: [URL]
    public let runtimeRevision: String
    public let rationale: String
  }

  public let context: Context
  public let prefill: Prefill
  public let generation: TextGenerationProfile
  public let conversation: ConversationPolicy
  public let evidence: Evidence

  public var isValid: Bool {
    context.isValid && prefill.isValid && generation.isValid && conversation.isValid
      && generation.conversation.outputTokens < context.workingTokens
      && generation.summary.outputTokens < context.workingTokens
      && conversation.safetyTokens < context.workingTokens
      && conversation.tools.reserveTokens < context.workingTokens
      && conversation.compaction.headroomTokens < context.workingTokens
      && [generation.conversation, generation.summary, generation.precise].allSatisfy {
        $0.reasoningTokens <= context.workingTokens - $0.outputTokens
      }
      && !evidence.runtimeRevision.isEmpty && !evidence.rationale.isEmpty
      && !evidence.sources.isEmpty && evidence.sources.allSatisfy { $0.scheme == "https" }
  }
}
