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
        "Find the user's saved screenshots, URLs, Stash items and meetings. Searches screenshot OCR, app names, transcripts and notes. Returns up to five ranked records, or recent records for an empty query. This is text search, not image recognition.",
      parameters: [
        .init(
          "query",
          description:
            "Short topic keywords, such as an app name or meeting subject. Use an empty string when listing a type of item without a topic, for example all saved URLs. Do not include words like show, find, screenshot or meeting or URL unless part of the actual topic."
        ),
        .init(
          "category", description: "The type of saved material to find.",
          kind: .choice(VaultSearchRequest.Category.allCases.map(\.rawValue))),
      ])
  }
  package func call(arguments: Data) async throws -> ConversationToolOutput {
    let args = try JSONDecoder().decode(Arguments.self, from: arguments)
    let matches = try await library.search(.init(query: args.query, category: args.category))
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
    return try VaultToolContent.output(sources)
  }
}
