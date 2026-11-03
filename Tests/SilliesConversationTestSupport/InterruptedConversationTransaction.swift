import Foundation
import SQLite3
import SilliesCore
import SilliesPersistence

/// Test-only fault injection between body and search-index writes, inside a real SQLite transaction.
/// The supervisor kills this process after the ready marker; no production hooks are required.
package final class InterruptedConversationTransaction {
  private var connection: OpaquePointer?
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  package init(directory: URL) throws {
    let fixture = try StoredConversationFixture.load(at: directory)
    var opened: OpaquePointer?
    let status = sqlite3_open_v2(
      directory.appendingPathComponent(ConversationDatabase.filename).path,
      &opened, SQLITE_OPEN_READWRITE, nil)
    guard status == SQLITE_OK, let opened else {
      if let opened { sqlite3_close(opened) }
      throw ConversationStorageError.invalidData
    }
    connection = opened
    do {
      try execute("BEGIN IMMEDIATE")
      let changed = fixture.landmarks[0].withText(
        String(repeating: "uncommittedneedle ", count: 30_000))
      try replaceBody(changed)
      try execute(
        "DELETE FROM conversation_search WHERE rowid=(SELECT MIN(sequence) FROM conversation_messages)"
      )
      guard sqlite3_changes(connection) == 1, sqlite3_get_autocommit(connection) == 0 else {
        throw ConversationStorageError.invalidData
      }
      // Force dirty pages into the WAL without committing, so recovery exercises disk state.
      try check(sqlite3_db_cacheflush(connection), expected: SQLITE_OK)
      try Data("transaction-open".utf8).write(
        to: directory.appendingPathComponent("transaction-open"), options: .atomic)
    } catch {
      sqlite3_close(connection)
      connection = nil
      throw error
    }
  }

  deinit { if let connection { sqlite3_close(connection) } }

  private func replaceBody(_ message: ChatMessage) throws {
    var statement: OpaquePointer?
    try check(
      sqlite3_prepare_v2(
        connection, "UPDATE conversation_messages SET body=? WHERE id=?", -1, &statement, nil),
      expected: SQLITE_OK)
    guard let statement else { throw ConversationStorageError.invalidData }
    defer { sqlite3_finalize(statement) }
    let data = try JSONEncoder().encode(message)
    try data.withUnsafeBytes {
      try check(
        sqlite3_bind_blob64(statement, 1, $0.baseAddress, UInt64($0.count), Self.transient),
        expected: SQLITE_OK)
    }
    let id = message.id.uuidString
    try check(sqlite3_bind_text(statement, 2, id, -1, Self.transient), expected: SQLITE_OK)
    try check(sqlite3_step(statement), expected: SQLITE_DONE)
    guard sqlite3_changes(connection) == 1 else { throw ConversationStorageError.invalidData }
  }

  private func execute(_ sql: String) throws {
    try check(sqlite3_exec(connection, sql, nil, nil, nil), expected: SQLITE_OK)
  }
  private func check(_ status: Int32, expected: Int32) throws {
    guard status == expected else {
      throw NSError(
        domain: "ConversationStorageProbe", code: Int(status),
        userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(connection))])
    }
  }
}
