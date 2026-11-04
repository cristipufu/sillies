import Foundation
import SilliesCore

extension ConversationSearchDatabase {
  public func memories(_ query: CompanionMemoryQuery) throws -> [CompanionMemory] {
    try sql.cancellableRead {
      guard
        try sql.integer(
          "SELECT COUNT(*) FROM conversations WHERE id=? AND generation=?",
          [.text(query.handle.companionID), .text(query.handle.generation.uuidString)]) == 1
      else { throw ConversationStorageError.changed }
      let owner = VaultSQLConnection.Value.text(query.handle.companionID)
      let limit = VaultSQLConnection.Value.integer(Int64(query.limit))
      if query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return try CompanionMemoryRows.read(
          from: sql,
          statement:
            "SELECT body FROM companion_memories WHERE owner=? ORDER BY updated DESC,id DESC LIMIT ?",
          values: [owner, limit])
      }
      guard let expression = VaultSearchTerms.expression(query.text, matching: .anyTerm) else {
        return []
      }
      return try CompanionMemoryRows.read(
        from: sql,
        statement: """
          WITH matches AS MATERIALIZED (
            SELECT m.rowid,bm25(memory_search) AS relevance
            FROM memory_search JOIN companion_memories m ON m.id=memory_search.id
            WHERE memory_search MATCH ? AND m.owner=?
            ORDER BY relevance,m.updated DESC,m.id DESC LIMIT ?
          )
          SELECT m.body FROM matches JOIN companion_memories m ON m.rowid=matches.rowid
          ORDER BY matches.relevance,m.updated DESC,m.id DESC
          """, values: [.text(expression), owner, limit])
    }
  }

}
