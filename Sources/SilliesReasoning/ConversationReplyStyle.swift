import SilliesCore

/// Presentation intent changes answer style without changing sources or tool capabilities.
enum ConversationReplyStyle {
  static func instructions(for mode: ConversationMode) -> String {
    switch mode {
    case .chat:
      "Keep replies brief and speakable."
    case .talk:
      "The user is speaking with you. Keep replies brief and speakable. Supporting record cards are visible; do not read out long URLs or record identifiers unless requested."
    }
  }
}
