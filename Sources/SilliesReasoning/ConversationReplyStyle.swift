import SilliesCore

/// Presentation intent changes answer style without changing sources or tool capabilities.
enum ConversationReplyStyle {
  static func instructions(for mode: ConversationMode) -> String {
    switch mode {
    case .chat:
      "Keep replies brief and speakable."
    case .talk:
      """
      The user is speaking with you and hears your answer aloud. Respond as one person talking to another, in natural conversational sentences.
      Give a short, direct answer, usually one to three sentences, and expand when the user asks for detail. Preserve the details needed to answer accurately.
      Use flowing speech, not bullet points, numbered lists, headings, bold text or other visual formatting. For instructions, connect the steps naturally with words such as first, then and finally.
      The user may not be looking at a screen. Explain the useful result in your answer; do not rely on visible cards or read out long URLs or record identifiers unless requested.
      """
    }
  }
}
