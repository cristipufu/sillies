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
    try prepareWorkspaceExcerptSelection(ids)
    var excerpts: [Int64: String] = [:]
    // Keep one FTS cursor and an indexed membership lookup. A VALUES-only CTE makes SQLite
    // scan every wanted ID for each matching passage when the selected blocks are far apart.
    try sql.rows(
      """
      SELECT \(plan.table).rowid,snippet(\(plan.table),0,'','',' … ',\(Self.workspaceExcerptTokens))
      FROM \(plan.table) CROSS JOIN temp.workspace_excerpt_selection wanted ON wanted.id=\(plan.table).rowid
      WHERE \(plan.table) MATCH ? AND \(plan.table).rowid>=? AND \(plan.table).rowid<=?
      """,
      [.text(plan.expression), .integer(first), .integer(last)]
    ) { row in
      guard let id = Int64(try VaultSQLConnection.text(row)) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      excerpts[id] = try VaultSQLConnection.text(row, column: 1)
    }
    return matches.map { $0.excerpt(excerpts[$0.blockID] ?? "") }
  }

  private func prepareWorkspaceExcerptSelection(_ ids: [Int64]) throws {
    // TEMP belongs only to this serialized reader, including when the archive is read-only.
    // Recreate after a rolled-back first read; retain no flag that can outlive the SQL schema.
    try sql.execute(
      "CREATE TEMP TABLE IF NOT EXISTS workspace_excerpt_selection(id INTEGER PRIMARY KEY)")
    try sql.execute("DELETE FROM temp.workspace_excerpt_selection")
    let placeholders = Array(repeating: "(?)", count: ids.count).joined(separator: ",")
    try sql.execute(
      "INSERT INTO temp.workspace_excerpt_selection VALUES \(placeholders)",
      ids.map(VaultSQLConnection.Value.integer))
  }
}
