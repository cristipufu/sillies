/// Checkpoint-level protocol, separate from its tensor architecture and tool format.
public enum TextModelReasoning: String, Codable, Equatable, Sendable {
  case switchableThinkTags
  case alwaysOnThinkTags

}
