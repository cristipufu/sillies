import Foundation
import SilliesCore

struct MemorySaveTool: ConversationTool {
  private struct Arguments: Decodable {
    let key: String
    let value: String
    let memoryID: String?
    let revision: String?

    func replacement() throws -> CompanionMemory.Reference? {
      guard memoryID != nil || revision != nil else { return nil }
      guard let memoryID, let revision, let id = UUID(uuidString: memoryID),
        let version = UUID(uuidString: revision)
      else { throw ReferenceError.invalid }
      return .init(id: id, revision: version)
    }
  }
  private enum ReferenceError: Error { case invalid }
  let repository: any CompanionMemoryRepository
  let handle: ConversationHandle
  let statement: ChatMessage
  var activity: String { String(localized: "Saving a memory…") }
  var definition: ConversationToolDefinition {
    .init(
      name: "save_memory",
      description:
        "Remember a lasting fact explicitly stated about the human user. Never save a question, fictional character fact, secret, or anything the user asks not to store. For a correction, search_memories first and pass the returned memoryID and revision to replace that fact. Only claim a fact was saved after this tool succeeds.",
      parameters: [
        .init("key", description: "Short stable topic key for this fact, reused for corrections."),
        .init("value", description: "The explicitly stated fact, preserving its meaning."),
        .init(
          "memoryID",
          description:
            "For a correction, the exact memoryID from search_memories. Omit for a new fact.",
          requirement: .optional),
        .init(
          "revision",
          description:
            "The revision returned with memoryID. Supply both for a correction; the existing topic key is retained.",
          requirement: .optional),
      ])
  }
  func call(arguments: Data) async throws -> ConversationToolOutput {
    let args = try JSONDecoder().decode(Arguments.self, from: arguments)
    guard statement.role == .user, !statement.text.isEmpty else {
      return .init(text: "Not saved: a current user statement is required.")
    }
    do {
      var write = MemoryWrite(
        handle: handle,
        fact: .init(key: args.key, value: args.value),
        source: .init(messageID: statement.id, quote: statement.text), savedAt: Date())
      if let reference = try args.replacement() { write = write.replacing(reference) }
      let receipt = try await repository.remember(write)
      return .init(text: "Memory saved. The app displays the fact and an Undo action.").remembering(
        receipt)
    } catch ReferenceError.invalid {
      return .init(
        text:
          "Not saved: a correction requires both the memoryID and revision from search_memories. Omit both for a new fact."
      )
    } catch MemoryMutationError.replacementChanged {
      return .init(
        text:
          "Not saved: the referenced memory is unavailable or has changed. Search memories again before correcting it."
      )
    }
  }
}
