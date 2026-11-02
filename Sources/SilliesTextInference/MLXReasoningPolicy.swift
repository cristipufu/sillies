import MLXLMCommon
import SilliesTextModels

/// Maps reviewed checkpoint capabilities to native prompt and channel conventions.
struct MLXReasoningPolicy {
  let preparation: TextModelPreparation

  var configuration: ReasoningConfig? {
    switch preparation.reasoning {
    case .alwaysOnThinkTags: .alwaysOnThinking
    case .switchableThinkTags: .thinkTagsWithEnableThinking
    case nil: nil
    }
  }

  var templateContext: [String: any Sendable] {
    switch preparation.reasoning {
    case .alwaysOnThinkTags: [:]
    case .switchableThinkTags, nil: ["enable_thinking": false]
    }
  }
}
