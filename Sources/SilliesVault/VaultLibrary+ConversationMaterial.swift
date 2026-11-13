import Foundation
import SilliesCore

extension VaultLibrary: ConversationMaterialProviding {
  package func selectedRecords(_ selection: ConversationRecordSelection, query: String) throws
    -> [ConversationRecordContext]
  {
    try selection.ids.map { id in
      try Task.checkCancellation()
      guard let document = try reasoningDocument(id: id) else {
        return .init(
          id: id, title: String(localized: "Unavailable Vault item"), source: nil, isComplete: false
        )
      }
      let passage = try VaultRecordPassage.select(
        in: document.content, query: query,
        maximumCharacters: ConversationRecordContext.maximumExcerptCharacters)
      let source = document.source(excerpt: passage.text).withPassages(
        try evidence(for: [passage], in: document))
      return .init(
        id: id, title: source.title, source: source,
        isComplete: passage.coverage.isComplete)
    }
  }
}
