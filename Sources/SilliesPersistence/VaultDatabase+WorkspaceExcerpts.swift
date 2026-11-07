import Foundation
import SilliesCore

extension VaultDatabase {
  private static let workspaceExcerptTokens = 24

  /// One FTS cursor serves the page. Reopening a prefix query for every preview repeatedly
  /// merges the archive's posting lists, even when each query selects just one block.
  func workspaceMatchHeaders(_ matches: [VaultWorkspaceMatch], plan: VaultTextSearchPlan) throws
    -> [VaultDocumentHeader]
  {
    guard matches.count <= VaultWorkspacePage.maximumCount + 1 else {
      throw VaultEditingError.invalidValue
    }
    let ids = matches.prefix(VaultWorkspacePage.maximumCount).map(\.blockID)
    guard let first = ids.min(), let last = ids.max() else { return [] }
    let placeholders = Array(repeating: "(?)", count: ids.count).joined(separator: ",")
    var excerpts: [Int64: String] = [:]
    // CROSS JOIN deliberately keeps FTS outermost so SQLite cannot restart MATCH per wanted ID.
    try sql.rows(
      """
      WITH wanted(id) AS MATERIALIZED (VALUES \(placeholders))
      SELECT \(plan.table).rowid,snippet(\(plan.table),0,'','',' … ',\(Self.workspaceExcerptTokens))
      FROM \(plan.table) CROSS JOIN wanted ON wanted.id=\(plan.table).rowid
      WHERE \(plan.table) MATCH ? AND \(plan.table).rowid>=? AND \(plan.table).rowid<=?
      """,
      ids.map(VaultSQLConnection.Value.integer)
        + [.text(plan.expression), .integer(first), .integer(last)]
    ) { row in
      guard let id = Int64(try VaultSQLConnection.text(row)) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      excerpts[id] = try VaultSQLConnection.text(row, column: 1)
    }
    return matches.map { $0.excerpt(excerpts[$0.blockID] ?? "") }
  }
}
