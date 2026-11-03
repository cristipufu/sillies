import MLXLMCommon

/// Routes provider protocol channels before any text reaches IPC, storage or speech.
struct MLXReasoningChannel {
  private var emitter: ReasoningEventEmitter?
  private var boundary: ReasoningResponseBoundary?
  private(set) var content = ""

  init(configuration: ModelConfiguration, promptTail: String) {
    let config = Self.configuration(for: configuration)
    boundary = config.map {
      // Gemma's opening control token and its channel name are separate tokens.
      // A missing or unknown name must not turn protocol output into visible prose.
      let opening = configuration.toolCallFormat == .gemma4 ? "<|channel>" : $0.startDelimiter
      return ReasoningResponseBoundary(delimiters: [opening, $0.endDelimiter])
    }
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

  mutating func append(_ text: String) throws -> String {
    guard let segments = emitter?.process(text) else { return text }
    return try route(segments)
  }

  mutating func finish() throws -> String {
    guard let segments = emitter?.finalize() else { return "" }
    return try route(segments) + (boundary?.finish() ?? "")
  }

  private mutating func route(_ segments: [ReasoningEventEmitter.Segment]) throws -> String {
    var visible = ""
    for segment in segments {
      switch segment {
      case .reasoning(let text): content += text
      case .response(let text): visible += try boundary?.append(text) ?? text
      }
    }
    return visible
  }
}
