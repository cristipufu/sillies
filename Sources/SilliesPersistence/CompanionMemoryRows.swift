import Foundation
import SilliesCore

/// Both ranked search and cursor pages decode only the bounded rows selected by their query.
enum CompanionMemoryRows {
  static func read(
    from sql: VaultSQLConnection, statement: String, values: [VaultSQLConnection.Value]
  )
    throws -> [CompanionMemory]
  {
    var facts: [CompanionMemory] = []
    let decoder = JSONDecoder()
    try sql.rows(statement, values) { row in
      try Task.checkCancellation()
      facts.append(
        try decoder.decode(
          CompanionMemory.self,
          from: VaultSQLConnection.data(
            row, maximumBytes: ConversationDatabase.maximumMemoryPayloadBytes)))
    }
    return facts
  }
}
