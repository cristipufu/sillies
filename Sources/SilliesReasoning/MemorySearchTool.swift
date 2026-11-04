import Foundation
import SilliesCore

struct MemorySearchTool: ConversationTool {
  private static let resultLimit = 4
  private static let statementCharacterLimit = 100
  let repository: any CompanionMemoryRepository
  let handle: ConversationHandle
  let companionName: String
  var activity: String { String(localized: "Checking memories…") }
  var definition: ConversationToolDefinition {
    .init(
      name: "search_memories",
      description:
        "Look up saved facts about the human user. These memories describe the user, not the assistant.",
      parameters: [
        .init("query", description: "A topic or question, or an empty string for recent memories.")
      ])
  }
  func call(arguments: Data) async throws -> ConversationToolOutput {
    let args = try ConversationToolArguments.decode(
      ConversationSearchArguments.self, from: arguments)
    let facts = try await repository.memories(
      .init(handle: handle, text: args.query, limit: Self.resultLimit))
    struct Fact: Encodable {
      let memoryID: UUID
      let revision: UUID
      let key: String
      let value: String
      let userStatement: String
    }
    struct Result: Encodable {
      let subject = "user"
      let attribution: String
      let relevance =
        "Ranked candidates may be unrelated. Use only facts that support the user's request; otherwise report no matching memory."
      let facts: [Fact]
    }
    let results = facts.prefix(Self.resultLimit).map {
      Fact(
        memoryID: $0.id, revision: $0.revision,
        key: $0.key, value: $0.value,
        userStatement: String($0.sourceQuote.prefix(Self.statementCharacterLimit)))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return .init(
      text: String(
        decoding: try encoder.encode(
          Result(
            attribution:
              "These facts describe the human chatting with \(companionName). They do not describe \(companionName).",
            facts: results)), as: UTF8.self))
  }
}
