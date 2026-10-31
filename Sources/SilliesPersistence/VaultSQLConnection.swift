import Foundation
import SQLite3

/// Confined to its repository's worker. All statements bind input; no external SQL fragments.
final class VaultSQLConnection {
  enum Value {
    case text(String)
    case integer(Int64)
    case real(Double)
    case data(Data)
    case null
  }
  private static let busyTimeoutMilliseconds: Int32 = 2_000
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  private let connection: OpaquePointer

  init(url: URL) throws {
    var opened: OpaquePointer?
    let result = sqlite3_open_v2(
      url.path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
    guard result == SQLITE_OK, let opened else {
      if let opened { sqlite3_close(opened) }
      throw VaultStorageError(message: "Could not open the Vault database (\(result)).")
    }
    connection = opened
    sqlite3_busy_timeout(opened, Self.busyTimeoutMilliseconds)
  }
  deinit { sqlite3_close(connection) }

  func execute(_ sql: String, _ values: [Value] = []) throws {
    try rows(sql, values) { _ in }
  }

  func transaction<T>(_ work: () throws -> T) throws -> T {
    try execute("BEGIN IMMEDIATE")
    do {
      let result = try work()
      try execute("COMMIT")
      return result
    } catch {
      do { try execute("ROLLBACK") } catch { fputs("Vault rollback failed: \(error)\n", stderr) }
      throw error
    }
  }

  func rows(_ sql: String, _ values: [Value] = [], consume: (OpaquePointer) throws -> Void) throws {
    var statement: OpaquePointer?
    try check(sqlite3_prepare_v2(connection, sql, -1, &statement, nil), expected: SQLITE_OK)
    guard let statement else {
      throw VaultStorageError(message: "Could not prepare the Vault query.")
    }
    defer { sqlite3_finalize(statement) }
    for (offset, value) in values.enumerated() {
      guard let index = Int32(exactly: offset + 1) else { throw CocoaError(.coderInvalidValue) }
      let result: Int32
      switch value {
      case .text(let text):
        result = sqlite3_bind_text64(
          statement, index, text, UInt64(text.utf8.count), Self.transient, UInt8(SQLITE_UTF8))
      case .integer(let number): result = sqlite3_bind_int64(statement, index, number)
      case .real(let number): result = sqlite3_bind_double(statement, index, number)
      case .null: result = sqlite3_bind_null(statement, index)
      case .data(let data):
        result = data.withUnsafeBytes { bytes in
          sqlite3_bind_blob64(
            statement, index, bytes.baseAddress, UInt64(bytes.count), Self.transient)
        }
      }
      try check(result, expected: SQLITE_OK)
    }
    var result = sqlite3_step(statement)
    while result == SQLITE_ROW {
      try consume(statement)
      result = sqlite3_step(statement)
    }
    try check(result, expected: SQLITE_DONE)
  }

  func integer(_ sql: String, _ values: [Value] = []) throws -> Int {
    var value = 0
    try rows(sql, values) { row in
      guard let decoded = Int(exactly: sqlite3_column_int64(row, 0)) else {
        throw CocoaError(.coderInvalidValue)
      }
      value = decoded
    }
    return value
  }

  static func data(_ row: OpaquePointer, column: Int32 = 0) throws -> Data {
    let count = sqlite3_column_bytes(row, column)
    guard count >= 0 else { throw CocoaError(.fileReadCorruptFile) }
    guard count > 0 else { return Data() }
    guard let bytes = sqlite3_column_blob(row, column) else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return Data(bytes: bytes, count: Int(count))
  }

  static func text(_ row: OpaquePointer, column: Int32 = 0) throws -> String {
    guard let text = sqlite3_column_text(row, column) else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return String(cString: text)
  }

  private func check(_ result: Int32, expected: Int32) throws {
    guard result == expected else {
      throw VaultStorageError(message: String(cString: sqlite3_errmsg(connection)))
    }
  }
}
