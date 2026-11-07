import Foundation
import SilliesCore

extension VaultDatabase {
  public func matchingPassages(recordID: UUID, query: VaultWorkspaceQuery) throws
    -> [VaultPassageMatch]
  {
    guard let plan = try VaultTextSearchPlan(query),
      let header = try documentHeader(id: recordID), header.metadata.trashedAt == nil
    else { return [] }
    return try sql.cancellableRead {
      var matches: [VaultPassageMatch] = []
      try sql.rows(
        """
        SELECT b.id,b.section,b.ordinal,coalesce(b.start_seconds,-1),snippet(\(plan.table),0,'','',' … ',24)
        FROM \(plan.table) JOIN content_blocks b ON b.id=\(plan.table).rowid
        WHERE \(plan.table) MATCH ? AND b.record_id=? ORDER BY \(plan.table).rank,b.id LIMIT ?
        """,
        [
          .text(plan.expression), .text(recordID.uuidString),
          .integer(Int64(VaultPassageMatch.maximumPerItem)),
        ]
      ) { row in
        guard let id = Int64(try VaultSQLConnection.text(row)),
          let section = VaultDocumentSection(rawValue: try VaultSQLConnection.text(row, column: 1)),
          let ordinal = Int(try VaultSQLConnection.text(row, column: 2)), ordinal >= 0
        else {
          throw CocoaError(.fileReadCorruptFile)
        }
        matches.append(
          .init(
            id: id, location: .init(recordID: recordID, section: section, ordinal: ordinal),
            excerpt: try VaultSQLConnection.text(row, column: 4),
            startSeconds: Double(try VaultSQLConnection.text(row, column: 3))))
      }
      return matches
    }
  }
}
