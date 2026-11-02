import MLXLMCommon

/// Routes provider protocol channels before any text reaches IPC, storage or speech.
struct MLXReasoningChannel {
  private var emitter: ReasoningEventEmitter?
  private(set) var content = ""

  init(configuration: ModelConfiguration, promptTail: String) {
    let config = Self.configuration(for: configuration)
    emitter = config.map {
      ReasoningEventEmitter(
        config: $0,
        primedInside: ReasoningEventEmitter.promptEndsInsideReasoning(
          renderedPromptTail: promptTail, config: $0))
    }
  }

  static func configuration(for model: ModelConfiguration) -> ReasoningConfig? {
    if let config = model.reasoningConfig { return config }
    // Gemma's template can emit thought channels even with thinking disabled.
    guard model.toolCallFormat == .gemma4 else { return nil }
    return .init(
      startDelimiter: "<|channel>thought", endDelimiter: "<channel|>",
      promptStrategy: .templateFlag(key: "enable_thinking", defaultOn: false))
  }

  mutating func append(_ text: String) -> String {
    guard let segments = emitter?.process(text) else { return text }
    return route(segments)
  }

  mutating func finish() -> String {
    guard let segments = emitter?.finalize() else { return "" }
    return route(segments)
  }

  private mutating func route(_ segments: [ReasoningEventEmitter.Segment]) -> String {
    var visible = ""
    for segment in segments {
      switch segment {
      case .reasoning(let text): content += text
      case .response(let text): visible += text
      }
    }
    return visible
  }
}
