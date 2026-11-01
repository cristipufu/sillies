import Foundation
import SilliesCore
import SilliesReasoning

package struct VaultReadTool: ConversationTool {
  private struct Arguments: Decodable {
    let recordID: UUID
    let query: String
  }
  private let library: VaultLibrary
  package init(library: VaultLibrary) { self.library = library }
  package var activity: String { String(localized: "Reading a saved item…") }
  package var definition: ConversationToolDefinition {
    .init(
      name: "read_vault_record",
      description:
        "Read a bounded passage from a record found by search_vault. Use the actual record ID. Returns source text and saved URLs, never image pixels.",
      parameters: [
        .init("recordID", description: "The exact UUID returned by search_vault."),
        .init(
          "query",
          description: "Topic words to locate the relevant passage, or empty for its beginning."),
      ])
  }
  package func call(arguments: Data) async throws -> ConversationToolOutput {
    let args = try JSONDecoder().decode(Arguments.self, from: arguments)
    guard let record = try await library.record(id: args.recordID) else {
      return .init(text: "The record is no longer available. It may have been deleted.")
    }
    try Task.checkCancellation()
    return try VaultToolContent.output([
      .init(
        header: .init(record),
        excerpt: VaultToolContent.excerpt(in: record, query: args.query),
        links: VaultToolContent.links(in: record))
    ])
  }
}
