import SilliesTextModels

/// Recovery is bounded to one attempt, before any response has been delivered.
enum ConversationRecovery {
  case reduceContext, repeatGeneration

  init?(_ error: any Error) {
    switch error {
    case TextModelError.contextLimit: self = .reduceContext
    case let failure as TextGenerationFailure where failure.reason == .invalidReasoningBoundary:
      self = .repeatGeneration
    default: return nil
    }
  }
}
