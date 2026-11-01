import Foundation
import SilliesCore

struct MemorySearchTool: ConversationTool {
  private static let resultLimit = 4
  let repository: any CompanionMemoryRepository
  let handle: ConversationHandle
  var activity: String { String(localized: "Checking memories…") }
  var definition: ConversationToolDefinition {
    .init(
      name: "search_memories",
      description:
        "Look up previously saved personal facts when the user asks about themselves.",
      parameters: [
        .init("query", description: "Topic keywords, or an empty string for recent memories.")
      ])
  }
  func call(arguments: Data) async throws -> ConversationToolOutput {
    let args = try JSONDecoder().decode(ConversationSearchArguments.self, from: arguments)
    let facts = try await repository.memories(handle, query: args.query)
    struct Fact: Encodable {
      let key: String
      let value: String
      let quote: String
    }
    let results = facts.prefix(Self.resultLimit).map {
      Fact(key: $0.key, value: $0.value, quote: String($0.sourceQuote.prefix(100)))
    }
    return .init(text: String(decoding: try JSONEncoder().encode(results), as: UTF8.self))
  }
}
