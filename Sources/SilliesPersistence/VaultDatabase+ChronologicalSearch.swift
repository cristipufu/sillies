import Foundation
import SilliesCore

extension VaultDatabase {
  private static let chronologicalSearchBatch = 256
  private static let sparseMatchLimit = 4_096

  /// Rare queries use the posting list directly. Broad date-ordered queries scan stable date
  /// slices instead of ranking the entire archive. A continuation also represents an empty slice.
  func dateOrderedSearchPage(_ query: VaultWorkspaceQuery, after cursor: VaultWorkspaceCursor?)
    throws
    -> VaultWorkspacePage
  {
    guard let plan = try VaultTextSearchPlan(query) else { return .init(records: [], next: nil) }
    let matches = try sql.integer(
      "SELECT count(*) FROM (SELECT rowid FROM \(plan.table) WHERE \(plan.table) MATCH ? LIMIT ?)",
      [.text(plan.expression), .integer(Int64(Self.sparseMatchLimit + 1))])
    if matches <= Self.sparseMatchLimit { return try rankedWorkspacePage(query, after: cursor) }
    let candidates = try searchDateCandidates(query, after: cursor)
    guard !candidates.isEmpty else { return .init(records: [], next: nil) }
    return try searchDateSlice(query, plan: plan, candidates: candidates)
  }

  private func searchDateCandidates(
    _ query: VaultWorkspaceQuery, after cursor: VaultWorkspaceCursor?
  ) throws
    -> [VaultWorkspaceCursor]
  {
    let order = VaultChronologicalOrder(query.ordering)
    let filter = VaultWorkspaceFilter(query)
    var result: [VaultWorkspaceCursor] = []
    try sql.rows(
      """
      SELECT r.id,\(order.value) FROM available_records r LEFT JOIN workspace w ON w.record_id=r.id
      WHERE \(filter.sql) \(order.continuation(after: cursor))
      ORDER BY \(order.value) \(order.direction),r.id \(order.direction) LIMIT ?
      """,
      filter.values + order.values(after: cursor) + [.integer(Int64(Self.chronologicalSearchBatch))]
    ) { row in
      guard let id = UUID(uuidString: try VaultSQLConnection.text(row)) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      result.append(.init(value: try VaultSQLConnection.real(row, column: 1), id: id))
    }
    return result
  }

  private func searchDateSlice(
    _ query: VaultWorkspaceQuery, plan: VaultTextSearchPlan, candidates: [VaultWorkspaceCursor]
  ) throws -> VaultWorkspacePage {
    let order = VaultChronologicalOrder(query.ordering)
    let filter = VaultWorkspaceFilter(query)
    let placeholders = Array(repeating: "(?,?)", count: candidates.count).joined(separator: ",")
    let values: [VaultSQLConnection.Value] = candidates.flatMap {
      [.text($0.id.uuidString), .real($0.value)]
    }
    var matches: [VaultWorkspaceMatch] = []
    try sql.rows(
      """
      WITH candidates(id,position) AS MATERIALIZED (VALUES \(placeholders)),
      bounds AS (
        SELECT min((SELECT min(id) FROM content_blocks WHERE record_id=c.id)) AS low,
          max((SELECT max(id) FROM content_blocks WHERE record_id=c.id)) AS high FROM candidates c),
      matches AS (
        SELECT b.record_id,c.position,b.id AS block_id,min(\(plan.table).rank) AS relevance
        FROM \(plan.table) JOIN content_blocks b ON b.id=\(plan.table).rowid
        JOIN candidates c ON c.id=b.record_id
        JOIN available_records r ON r.id=b.record_id LEFT JOIN workspace w ON w.record_id=r.id
        WHERE \(plan.table) MATCH ? AND \(plan.table).rowid>=(SELECT low FROM bounds)
          AND \(plan.table).rowid<=(SELECT high FROM bounds)
          AND \(filter.sql)
        GROUP BY b.record_id ORDER BY c.position \(order.direction),b.record_id \(order.direction) LIMIT ?)
      SELECT r.header,w.metadata,m.position,b.section,b.ordinal,b.id,coalesce(b.start_seconds,-1)
      FROM matches m JOIN available_records r ON r.id=m.record_id
      LEFT JOIN workspace w ON w.record_id=r.id JOIN content_blocks b ON b.id=m.block_id
      WHERE \(filter.sql) ORDER BY m.position \(order.direction),m.record_id \(order.direction)
      """,
      values + [.text(plan.expression)] + filter.values + [
        .integer(Int64(VaultWorkspacePage.maximumCount + 1))
      ] + filter.values
    ) { row in
      matches.append(try workspaceMatch(row))
    }
    let headers = try workspaceMatchHeaders(matches, plan: plan)
    if headers.count > VaultWorkspacePage.maximumCount {
      return workspacePage(headers, values: matches.map(\.position))
    }
    return .init(
      records: headers,
      next: candidates.count == Self.chronologicalSearchBatch ? candidates.last : nil)
  }
}
