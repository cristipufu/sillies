import SilliesCore
import SilliesTextModels

/// Generated notes are fallible conversation data, never developer instructions.
enum ConversationContextNotes {
  static func applying(_ memory: ConversationMemory, to messages: [TextMessage]) -> [TextMessage] {
    guard memory.throughMessageID != nil, let first = messages.first, first.role == .user else {
      return messages
    }
    let references = memory.references.map { "\($0.id.uuidString): \($0.title)" }.joined(
      separator: "\n")
    let contextualized = TextMessage(
      role: .user,
      content: """
        Background from the earlier conversation, supplied by the app as source data:
        Original user opening (excerpt):
        \(memory.openingStatement)

        Generated notes (possibly incomplete or mistaken; recent source statements take precedence):
        \(memory.summary)

        Previously retrieved record references (read again to verify details):
        \(references)
        End of background.

        Original user message:
        \(first.content)
        """)
    // Keep native role alternation, including templates that reject consecutive user entries.
    return [contextualized] + messages.dropFirst()
  }
}
