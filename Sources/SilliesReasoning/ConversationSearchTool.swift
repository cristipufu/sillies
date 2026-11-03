import Foundation
import SilliesCore

struct ConversationSearchTool: ConversationTool {
  private static let resultLimit = 4
  private static let excerptLimit = 600
  let repository: any ConversationRepository
  let handle: ConversationHandle
  let currentMessageID: UUID
  var activity: String { String(localized: "Searching our conversation…") }
  var definition: ConversationToolDefinition {
    .init(
      name: "search_conversation",
      description:
        "Retrieve earlier messages, shared plans and decisions from this continuing conversation. Search here for prior chat details omitted from the current context. For saved meetings, screenshots or Stash items use search_vault instead.",
      parameters: [.init("query", description: "Short topic keywords from the earlier discussion.")]
    )
  }
  func call(arguments: Data) async throws -> ConversationToolOutput {
    let args = try ConversationToolArguments.decode(
      ConversationSearchArguments.self, from: arguments)
    let matches = try await repository.search(
      .init(
        companionID: handle.companionID,
        query: args.query, limit: Self.resultLimit, excludingMessageID: currentMessageID))
    struct Result: Encodable {
      let messageID: UUID
      let date: Date
      let speaker: String
      let excerpt: String
    }
    let results = matches.map { match in
      Result(
        messageID: match.id, date: match.entry.createdAt,
        speaker: match.entry.message.role == .user ? "user" : "companion",
        excerpt: String(match.entry.message.text.prefix(Self.excerptLimit)))
    }
    return .init(text: String(decoding: try JSONEncoder().encode(results), as: UTF8.self))
  }
}
