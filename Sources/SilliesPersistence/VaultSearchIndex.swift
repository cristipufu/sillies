import Foundation
import SQLite3
import SilliesCore

/// Rebuildable local FTS cache. One background owner must serialize access to this connection.
public final class VaultSearchIndex {
  private static let maximumQueryTokens = 32
  private var database: OpaquePointer?
  private var identifiers: Set<UUID> = []
  public private(set) var indexedDocumentCount = 0
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  public init(directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var connection: OpaquePointer?
    let path = directory.appendingPathComponent("search.sqlite").path
    let status = sqlite3_open_v2(
      path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
    guard status == SQLITE_OK, let connection else {
      if let connection { sqlite3_close(connection) }
      throw SearchIndexError(message: "Could not open the local search index (\(status)).")
    }
    database = connection
    do {
      try execute("PRAGMA journal_mode=MEMORY")
      try execute("PRAGMA secure_delete=ON")
      try execute(
        "CREATE VIRTUAL TABLE IF NOT EXISTS documents USING fts5(id UNINDEXED, kind UNINDEXED, body, tokenize='unicode61 remove_diacritics 2')"
      )
      // Records are authoritative; never expose stale/deleted text left by an interrupted run.
      try execute("DELETE FROM documents")
    } catch {
      sqlite3_close(connection)
      database = nil
      throw error
    }
  }
  deinit { if let database { sqlite3_close(database) } }
  public static func erase(directory: URL) throws {
    try VaultFileStorage(directory: directory).write(Data(), named: "search.sqlite")
  }

  public func synchronize(_ records: [SessionRecord]) throws {
    try apply(upserting: records, removing: identifiers.subtracting(records.map(\.id)))
  }

  public func apply(upserting records: [SessionRecord], removing deleted: Set<UUID>) throws {
    try execute("BEGIN IMMEDIATE")
    do {
      for id in deleted {
        try execute("DELETE FROM documents WHERE id = ?", values: [id.uuidString])
      }
      for record in records {
        try execute("DELETE FROM documents WHERE id = ?", values: [record.id.uuidString])
        try execute(
          "INSERT INTO documents(id,kind,body) VALUES(?,?,?)",
          values: [record.id.uuidString, record.kind.rawValue, Self.body(record)])
      }
      try execute("COMMIT")
      identifiers.subtract(deleted)
      identifiers.formUnion(records.map(\.id))
      indexedDocumentCount += records.count
    } catch {
      do { try execute("ROLLBACK") } catch { fputs("Search rollback failed: \(error)\n", stderr) }
      throw error
    }
  }

  public func search(_ query: String, kind: CompanionSkillKind?) throws -> Set<UUID> {
    let tokens = query.split { !$0.isLetter && !$0.isNumber && $0 != "_" }
    guard !tokens.isEmpty else { return [] }
    let expression = tokens.prefix(Self.maximumQueryTokens).map { "\"\($0)\"*" }.joined(
      separator: " AND ")
    var values = [expression]
    var sql = "SELECT id FROM documents WHERE documents MATCH ?"
    if let kind {
      sql += " AND kind = ?"
      values.append(kind.rawValue)
    }
    return Set(
      try statement(sql, values: values) { statement in
        var identifiers: [UUID] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
          if let value = sqlite3_column_text(statement, 0),
            let id = UUID(uuidString: String(cString: value))
          {
            identifiers.append(id)
          }
          status = sqlite3_step(statement)
        }
        try check(status, expected: SQLITE_DONE)
        return identifiers
      })
  }

  public static func body(_ record: SessionRecord) -> String {
    ([
      record.displayTitle, record.appName, record.summary, record.transcript,
      record.extractedText, record.explanation,
    ] + record.actionItems + record.stashedItems)
    .joined(separator: "\n")
  }

  private func execute(_ sql: String, values: [String] = []) throws {
    try statement(sql, values: values) {
      var status = sqlite3_step($0)
      while status == SQLITE_ROW { status = sqlite3_step($0) }
      try check(status, expected: SQLITE_DONE)
    }
  }
  private func statement<T>(_ sql: String, values: [String], run: (OpaquePointer) throws -> T)
    throws -> T
  {
    var prepared: OpaquePointer?
    try check(sqlite3_prepare_v2(database, sql, -1, &prepared, nil), expected: SQLITE_OK)
    guard let prepared else {
      throw SearchIndexError(message: "Could not prepare a search statement.")
    }
    defer { sqlite3_finalize(prepared) }
    for (offset, value) in values.enumerated() {
      try check(
        sqlite3_bind_text(prepared, Int32(offset + 1), value, -1, Self.transient),
        expected: SQLITE_OK)
    }
    return try run(prepared)
  }
  private func check(_ status: Int32, expected: Int32) throws {
    guard status == expected else {
      throw SearchIndexError(message: String(cString: sqlite3_errmsg(database)))
    }
  }
}

public struct SearchIndexError: Error, LocalizedError {
  public let message: String
  public var errorDescription: String? { message }
}
