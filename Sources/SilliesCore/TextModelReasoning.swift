/// Checkpoint-level protocol, separate from its tensor architecture and tool format.
public enum TextModelReasoning: String, Codable, Equatable, Sendable {
  case switchableThinkTags
  case alwaysOnThinkTags

  /// Extra generation allowance for models that cannot turn off private reasoning.
  /// This remains bounded by the shared context window and request deadline.
  public var tokenReserve: Int {
    switch self {
    case .switchableThinkTags: 0
    case .alwaysOnThinkTags: 1_024
    }
  }
}
