import Foundation
import SilliesCore
import SilliesReasoning

package struct VaultReadTool: ConversationTool {
  private struct Arguments: Decodable {
    let recordID: UUID
    let query: String
    let offset: Int?
  }
  private let library: VaultLibrary
  package init(library: VaultLibrary) { self.library = library }
  package var activity: String { String(localized: "Reading a saved item…") }
  package var definition: ConversationToolDefinition {
    .init(
      name: "read_vault_record",
      description:
        "Read a search_vault result when its excerpt does not answer the question. Requires a real result ID.",
      parameters: [
        .init("recordID", description: "The exact UUID returned by search_vault."),
        .init(
          "query",
          description: "Topic words to locate the relevant passage, or empty for its beginning."),
        .init(
          "offset",
          description:
            "Omit to find a passage by query. Use nextOffset from a prior read to continue, or 0 for the beginning.",
          kind: .integer, requirement: .optional),
      ])
  }
  package func call(arguments: Data) async throws -> ConversationToolOutput {
    let args = try JSONDecoder().decode(Arguments.self, from: arguments)
    guard let record = try await library.record(id: args.recordID) else {
      return .init(text: "The record is no longer available. It may have been deleted.")
    }
    try Task.checkCancellation()
    do {
      let passage = try VaultRecordPassage.select(
        in: record, query: args.query, offset: args.offset)
      let source = try ChatSource(
        header: .init(record), excerpt: passage.text, links: VaultToolContent.links(in: record))
      return try VaultToolContent.readOutput(source, passage: passage)
    } catch VaultRecordPassage.SelectionError.invalidOffset {
      return .init(
        text:
          "No passage was read: the offset is outside the current record. Retry without offset to select a passage by query."
      )
    }
  }
}
