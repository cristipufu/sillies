import Foundation
import SilliesCore

struct ConversationSearchTool: ConversationTool {
  private static let resultLimit = 4
  private static let compactResultLimits = [2, 1]
  let repository: any ConversationRepository
  let handle: ConversationHandle
  let currentMessageID: UUID
  var activity: String { String(localized: "Searching our conversation…") }
  var definition: ConversationToolDefinition {
    .init(
      name: "search_conversation",
      description:
        "Search the saved chat with this companion for earlier statements, shared plans and decisions missing from the visible conversation. Returns relevant excerpts with speakers and message order. For recorded meetings, screenshots or Stash items use search_vault instead.",
      parameters: [
        .init(
          "query",
          description:
            "Required topic keywords from the earlier discussion. Narrow them to locate a detail within a long message."
        )
      ]
    )
  }
  func call(arguments: Data) async throws -> ConversationToolOutput {
    let args = try ConversationToolArguments.decode(
      ConversationSearchArguments.self, from: arguments)
    let query = args.query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matches = try await repository.search(
      .init(
        companionID: handle.companionID,
        query: query, limit: Self.resultLimit + 1, excludingMessageID: currentMessageID))
    let text = try ConversationSearchEvidence(
      query: query, matches: matches, limit: Self.resultLimit
    )
    .encoded()
    let alternatives = try Self.compactResultLimits.filter { $0 < matches.count }.map { limit in
      try ConversationSearchEvidence(query: query, matches: matches, limit: limit).encoded()
    }
    return .init(text: text, briefText: alternatives.last ?? text, alternatives: alternatives)
  }
}
