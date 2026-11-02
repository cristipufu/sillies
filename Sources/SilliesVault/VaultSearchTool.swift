import Foundation
import SilliesCore
import SilliesReasoning

package struct VaultSearchTool: ConversationTool {
  private static let excerptCharacters = 240
  private struct Arguments: Decodable {
    let query: String
    let category: VaultSearchRequest.Category
  }
  private let library: VaultLibrary
  package init(library: VaultLibrary) { self.library = library }
  package var activity: String { String(localized: "Searching your Vault…") }
  package var definition: ConversationToolDefinition {
    .init(
      name: "search_vault",
      description:
        "Find the user's saved screenshots, links, Stash items and meetings. Returns excerpts and display cards, not web results.",
      parameters: [
        .init(
          "category", description: "The type of saved material to find.",
          kind: .choice(VaultSearchRequest.Category.allCases.map(\.rawValue))),
        .init(
          "query",
          description:
            "Topic keywords within that category, such as an app name or meeting subject. Empty string lists the category. For saved URLs: category=links, query=\"\"."
        ),
      ])
  }
  package func call(arguments: Data) async throws -> ConversationToolOutput {
    let args = try JSONDecoder().decode(Arguments.self, from: arguments)
    let request = VaultSearchRequest(query: args.query, category: args.category)
    let matches = try await library.search(request)
    var sources: [ChatSource] = []
    for match in matches {
      try Task.checkCancellation()
      let links: [URL]
      if args.category == .links, let record = try await library.record(id: match.header.id) {
        links = try VaultToolContent.links(in: record)
        if links.isEmpty { continue }
      } else {
        links = []
      }
      sources.append(
        .init(
          header: match.header, excerpt: String(match.excerpt.prefix(Self.excerptCharacters)),
          links: links))
    }
    let total = try await library.page(.init(limit: 1)).total
    return try VaultToolContent.searchOutput(sources, request: request, totalVaultRecords: total)
  }
}
