import Foundation
import SilliesCore

/// A complete page of eligible records proves an upper bound on the first page's worst rank.
/// Sampling establishes only that bound: the final query still scores every matching block.
struct VaultSearchRankBoundary {
  let score: Double
  let recordID: String

  var predicate: String {
    "WHERE relevance<? OR (relevance=? AND record_id<=?)"
  }
  var values: [VaultSQLConnection.Value] {
    [.real(score), .real(score), .text(recordID)]
  }
}

extension VaultDatabase {
  private static let maximumRankSeedBlocks = 4_096
  private static let maximumRankRecordIDBytes = 36

  /// Bounds only the first page. A continuation must aggregate every record's best block before
  /// applying its cursor, otherwise a weaker block can reintroduce an earlier result.
  func firstPageRankBoundary(_ plan: VaultTextSearchPlan, filter: VaultWorkspaceFilter) throws
    -> VaultSearchRankBoundary?
  {
    let records = supportsSearchMetadata ? "available_search_records" : "available_records"
    let pageCount = VaultWorkspacePage.maximumCount + 1
    var boundary: VaultSearchRankBoundary?
    try sql.rows(
      """
      WITH sampled AS MATERIALIZED (\(plan.scoredBlocksSQL) LIMIT ?),
      seed AS MATERIALIZED (
        SELECT s.record_id,min(s.relevance) AS relevance FROM sampled s
        JOIN \(records) r ON r.id=s.record_id LEFT JOIN workspace w ON w.record_id=r.id
        WHERE \(filter.sql) GROUP BY s.record_id
        ORDER BY relevance,s.record_id LIMIT ?)
      SELECT record_id,relevance FROM seed WHERE (SELECT count(*) FROM seed)=?
      ORDER BY relevance DESC,record_id DESC LIMIT 1
      """,
      [.text(plan.expression), .integer(Int64(Self.maximumRankSeedBlocks))] + filter.values
        + [.integer(Int64(pageCount)), .integer(Int64(pageCount))]
    ) { row in
      let id = try VaultSQLConnection.text(row, maximumBytes: Self.maximumRankRecordIDBytes)
      guard UUID(uuidString: id) != nil else { throw CocoaError(.fileReadCorruptFile) }
      boundary = .init(score: try VaultSQLConnection.real(row, column: 1), recordID: id)
    }
    return boundary
  }
}
