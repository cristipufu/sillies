import Foundation
import SilliesCore

extension VaultLibrary: ConversationMaterialProviding {
  package func selectedRecords(_ selection: ConversationRecordSelection, query: String) throws
    -> [ConversationRecordContext]
  {
    try selection.ids.map { id in
      try Task.checkCancellation()
      guard let record = try record(id: id) else {
        return .init(
          id: id, title: String(localized: "Unavailable Vault item"), source: nil, isComplete: false
        )
      }
      let passage = try VaultRecordPassage.select(
        in: record, query: query,
        maximumCharacters: ConversationRecordContext.maximumExcerptCharacters)
      let source = try ChatSource(
        header: .init(record), excerpt: passage.text, links: VaultToolContent.links(in: record))
      return .init(
        id: id, title: source.title, source: source,
        isComplete: passage.coverage.isComplete)
    }
  }
}
