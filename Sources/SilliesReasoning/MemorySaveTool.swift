import Foundation
import SilliesCore

struct MemorySaveTool: ConversationTool {
  private struct Arguments: Decodable {
    let key: String
    let value: String
  }
  let repository: any CompanionMemoryRepository
  let handle: ConversationHandle
  let statement: ChatMessage
  var activity: String { String(localized: "Saving a memory…") }
  var definition: ConversationToolDefinition {
    .init(
      name: "save_memory",
      description:
        "Remember a lasting fact explicitly stated about the human user. Never save a question, fictional character fact, secret, or anything the user asks not to store. A correction replaces the same topic key. Only claim a fact was saved after this tool succeeds.",
      parameters: [
        .init("key", description: "Short stable topic key for this fact, reused for corrections."),
        .init("value", description: "The explicitly stated fact, preserving its meaning."),
      ])
  }
  func call(arguments: Data) async throws -> ConversationToolOutput {
    let args = try JSONDecoder().decode(Arguments.self, from: arguments)
    guard statement.role == .user, !statement.text.isEmpty else {
      return .init(text: "Not saved: a current user statement is required.")
    }
    let receipt = try await repository.remember(
      .init(
        handle: handle,
        fact: .init(key: args.key, value: args.value),
        source: .init(messageID: statement.id, quote: statement.text), savedAt: Date()))
    return .init(text: "Memory saved. The app displays the fact and an Undo action.").remembering(
      receipt)
  }
}
