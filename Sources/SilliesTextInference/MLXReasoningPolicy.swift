import MLXLMCommon
import SilliesTextModels

/// Maps reviewed checkpoint capabilities to native prompt and channel conventions.
struct MLXReasoningPolicy {
  let reasoning: TextModelPreparation.Reasoning?

  var configuration: ReasoningConfig? {
    switch reasoning {
    case .alwaysOnThinkTags: .alwaysOnThinking
    case .switchableThinkTags: .thinkTagsWithEnableThinking
    case nil: nil
    }
  }

  var templateContext: [String: any Sendable] {
    switch reasoning {
    case .alwaysOnThinkTags: [:]
    case .switchableThinkTags, nil: ["enable_thinking": false]
    }
  }
}
