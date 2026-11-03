import Foundation
import SilliesCore

/// A read-only WAL connection. Ranking never occupies the writer's actor or blocks its commits.
public final class ConversationSearchDatabase {
  private let sql: VaultSQLConnection
  private let rows = ConversationRowDecoder()

  public init(directory: URL) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    sql = try VaultSQLConnection(
      url: directory.appendingPathComponent(ConversationDatabase.filename), access: .readOnly)
    guard try sql.integer("PRAGMA user_version") == ConversationDatabase.schemaVersion else {
      throw ConversationStorageError.unsupportedVersion
    }
  }

  public func search(_ request: ConversationSearchRequest) throws -> [ConversationSearchMatch] {
    try sql.cancellableRead { try matches(request) }
  }

  private func matches(_ request: ConversationSearchRequest) throws -> [ConversationSearchMatch] {
    guard let expression = VaultSearchTerms.expression(request.query, matching: .anyTerm) else {
      return []
    }
    var filter = "conversation_search MATCH ?"
    var values: [VaultSQLConnection.Value] = [.text(expression)]
    if let owner = request.companionID {
      filter += " AND m.owner=?"
      values.append(.text(owner))
    }
    if let excluded = request.excludingMessageID {
      filter += " AND m.id != ?"
      values.append(.text(excluded.uuidString))
    }
    var results: [ConversationSearchMatch] = []
    // Rank numeric message identities first. Bodies and owner names are fetched only for the
    // bounded result set, not for every candidate that enters the ranking sort.
    try sql.rows(
      """
      WITH matches AS MATERIALIZED (
        SELECT m.sequence,bm25(conversation_search) AS relevance
        FROM conversation_search
        JOIN conversation_messages m ON m.sequence=conversation_search.rowid
        WHERE \(filter)
        ORDER BY relevance,m.sequence DESC LIMIT ?
      )
      SELECT m.sequence,m.created,m.body,c.id,c.name FROM matches
      JOIN conversation_messages m ON m.sequence=matches.sequence
      JOIN conversations c ON c.id=m.owner
      ORDER BY matches.relevance,m.sequence DESC
      """,
      values + [.integer(Int64(request.limit))]
    ) { row in
      results.append(
        try .init(
          owner: .init(
            id: VaultSQLConnection.text(row, column: 3),
            name: VaultSQLConnection.text(row, column: 4)), entry: rows.entry(row)))
    }
    return results
  }

}
