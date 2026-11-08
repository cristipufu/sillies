import Foundation
import SilliesCore

/// FTS table names come from a closed policy; user syntax is always a quoted literal.
struct VaultTextSearchPlan {
  static let maximumQueryScalars = 512
  let table: String
  let expression: String
  var scoredBlocksSQL: String {
    """
    SELECT b.record_id,rank AS relevance,b.id AS block_id
    FROM \(table) JOIN content_blocks b INDEXED BY content_block_identity ON b.id=\(table).rowid
    WHERE \(table) MATCH ?
    """
  }

  init?(_ query: VaultWorkspaceQuery) throws {
    let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.unicodeScalars.count <= Self.maximumQueryScalars else {
      throw VaultEditingError.searchTooLong
    }
    guard !text.contains("\0") else { throw VaultEditingError.invalidValue }
    guard !text.isEmpty else { return nil }
    switch query.textMatching ?? .words {
    case .words:
      guard let expression = VaultSearchTerms.expression(text, matching: .anyTerm) else {
        return nil
      }
      table = "content_search"
      self.expression = expression
    case .phrase:
      table = "content_search"
      expression = "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    case .literal:
      guard text.unicodeScalars.count >= 3 else { throw VaultEditingError.searchTooShort }
      table = "content_substrings"
      expression = "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
  }
}
