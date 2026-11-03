/// Task-specific decoding settings. Reasoning capacity is accounted for by both admission and runtime.
public struct TextGenerationProfile: Codable, Equatable, Sendable {
  public struct Task: Codable, Equatable, Sendable {
    public let outputTokens: Int
    public let reasoningTokens: Int
    public let sampling: TextModelSampling
    public let repetitionContextTokens: Int
    public init(
      outputTokens: Int, reasoningTokens: Int, sampling: TextModelSampling,
      repetitionContextTokens: Int
    ) {
      self.outputTokens = outputTokens
      self.reasoningTokens = reasoningTokens
      self.sampling = sampling
      self.repetitionContextTokens = repetitionContextTokens
    }

    public var isValid: Bool {
      outputTokens > 0 && reasoningTokens >= 0 && sampling.isValid
        && repetitionContextTokens >= 0
        && !outputTokens.addingReportingOverflow(reasoningTokens).overflow
    }

    /// A caller can ask for less output; the model's reviewed task allowance remains the ceiling.
    public func generationTokens(for requestedOutputTokens: Int) -> Int? {
      guard isValid, requestedOutputTokens > 0 else { return nil }
      return min(requestedOutputTokens, outputTokens) + reasoningTokens
    }
  }

  public let conversation: Task
  public let summary: Task
  public let precise: Task
  public init(conversation: Task, summary: Task, precise: Task) {
    self.conversation = conversation
    self.summary = summary
    self.precise = precise
  }
  public var isValid: Bool { conversation.isValid && summary.isValid && precise.isValid }
}
