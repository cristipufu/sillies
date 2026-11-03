import Foundation
import SQLite3
import SilliesCore

/// Both paged reads and search restore interrupted delivery with the same byte boundary.
struct ConversationRowDecoder {
  let json = JSONDecoder()

  func entry(_ row: OpaquePointer) throws -> ConversationEntry {
    let data = try VaultSQLConnection.data(
      row, column: 2, maximumBytes: ConversationDatabase.maximumMessageBytes)
    var message = try json.decode(ChatMessage.self, from: data)
    if message.completion == .streaming {
      message = message.withDelivery(.interrupted, spokenText: message.spokenText)
    }
    return .init(
      sequence: sqlite3_column_int64(row, 0), message: message,
      createdAt: Date(timeIntervalSince1970: sqlite3_column_double(row, 1)))
  }
}
