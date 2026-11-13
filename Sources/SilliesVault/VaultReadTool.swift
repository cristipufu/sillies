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
        "Read a selected Vault item or a search result when its excerpt does not answer the question. Requires a real record ID.",
      parameters: [
        .init(
          "recordID",
          description: "The exact UUID of a selected Vault item or a search_vault result."),
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
    let args = try ConversationToolArguments.decode(Arguments.self, from: arguments)
    guard let document = try await library.reasoningDocument(id: args.recordID) else {
      return .init(text: "The record is no longer available. It may have been deleted.")
    }
    try Task.checkCancellation()
    do {
      let passages = try VaultRecordPassage.selectRelated(
        in: document.content, query: args.query, offset: args.offset)
      guard !passages.isEmpty else {
        throw VaultRecordPassage.SelectionError.invalidOffset
      }
      var sources: [ChatSource] = []
      for part in passages {
        let evidence = try await library.evidence(for: [part], in: document)
        sources.append(document.source(excerpt: part.text).withPassages(evidence))
      }
      return try VaultToolContent.readOutput(sources, passages: passages)
    } catch VaultRecordPassage.SelectionError.invalidOffset {
      return .init(
        text:
          "No passage was read: the offset is outside the current record. Retry without offset to select a passage by query."
      )
    }
  }

}
