import Foundation
import SQLite3
import SilliesCore

extension ConversationDatabase {
  public func page(_ request: ConversationPageRequest) throws -> ConversationPage {
    try validate(request.handle)
    let owner = request.handle.companionID
    var predicate = "owner=?"
    var values: [VaultSQLConnection.Value] = [.text(owner)]
    var order = "DESC"
    switch request.position {
    case .latest: break
    case .before(let sequence):
      predicate += " AND sequence<?"
      values.append(.integer(sequence))
    case .beforeMessage(let id):
      predicate += " AND sequence<?"
      values.append(.integer(try sequence(of: id, owner: owner)))
    case .throughMessage(let id):
      predicate += " AND sequence<=?"
      values.append(.integer(try sequence(of: id, owner: owner)))
    case .between(let after, let before):
      predicate += " AND sequence>? AND sequence<?"
      values.append(.integer(try after.map { try sequence(of: $0, owner: owner) } ?? 0))
      values.append(.integer(try sequence(of: before, owner: owner)))
      order = "ASC"
    case .after(let sequence):
      predicate += " AND sequence>?"
      values.append(.integer(sequence))
      order = "ASC"
    case .around(let id):
      predicate += " AND sequence>=?"
      values.append(.integer(try sequence(of: id, owner: owner)))
      order = "ASC"
    }
    var entries: [ConversationEntry] = []
    var bytes = 0
    var reachedByteLimit = false
    try sql.rows(
      "SELECT sequence,created,body FROM conversation_messages WHERE \(predicate) ORDER BY sequence \(order) LIMIT ?",
      values + [.integer(Int64(request.limit))]
    ) { row in
      guard !reachedByteLimit else { return }
      let size = Int(sqlite3_column_bytes(row, 2))
      guard size <= request.maximumBytes - bytes || entries.isEmpty else {
        reachedByteLimit = true
        return
      }
      // One oversized row still makes cursor progress; its independent 1 MiB boundary applies.
      entries.append(try entry(row))
      bytes += size
      reachedByteLimit = bytes >= request.maximumBytes
    }
    if order == "DESC" { entries.reverse() }
    let older =
      try entries.first.map { first in
        try sql.integer(
          "SELECT EXISTS(SELECT 1 FROM conversation_messages WHERE owner=? AND sequence<?)",
          [.text(owner), .integer(first.sequence)]) != 0
      } ?? false
    let newer =
      try entries.last.map { last in
        try sql.integer(
          "SELECT EXISTS(SELECT 1 FROM conversation_messages WHERE owner=? AND sequence>?)",
          [.text(owner), .integer(last.sequence)]) != 0
      } ?? false
    return .init(
      entries: entries, hasOlder: older, hasNewer: newer, isByteLimited: reachedByteLimit)
  }

  public func search(_ request: ConversationSearchRequest) throws -> [ConversationSearchMatch] {
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
    try sql.rows(
      "SELECT m.sequence,m.created,m.body,c.id,c.name FROM conversation_search JOIN conversation_messages m ON m.id=conversation_search.id JOIN conversations c ON c.id=m.owner WHERE \(filter) ORDER BY bm25(conversation_search),m.sequence DESC LIMIT ?",
      values + [.integer(Int64(request.limit))]
    ) { row in
      results.append(
        try .init(
          owner: .init(
            id: VaultSQLConnection.text(row, column: 3),
            name: VaultSQLConnection.text(row, column: 4)), entry: entry(row)))
    }
    return results
  }

  func sequence(of id: UUID, owner: String) throws -> Int64 {
    let value = try sql.integer(
      "SELECT sequence FROM conversation_messages WHERE owner=? AND id=?",
      [.text(owner), .text(id.uuidString)])
    guard value > 0 else { throw ConversationStorageError.changed }
    return Int64(value)
  }

  public func conversations() throws -> [ConversationHeader] {
    var headers: [ConversationHeader] = []
    try sql.rows(
      "SELECT c.id,c.name,c.updated,(SELECT COUNT(*) FROM conversation_messages m WHERE m.owner=c.id),(SELECT m.preview FROM conversation_messages m WHERE m.owner=c.id ORDER BY m.sequence DESC LIMIT 1) FROM conversations c ORDER BY c.updated DESC LIMIT 200"
    ) { row in
      guard let count = Int(exactly: sqlite3_column_int64(row, 3)) else {
        throw ConversationStorageError.invalidData
      }
      let excerpt =
        sqlite3_column_type(row, 4) == SQLITE_NULL
        ? "" : try VaultSQLConnection.text(row, column: 4)
      headers.append(
        try .init(
          owner: .init(
            id: VaultSQLConnection.text(row), name: VaultSQLConnection.text(row, column: 1)),
          updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(row, 2)),
          messageCount: count, excerpt: excerpt))
    }
    return headers
  }

  private func entry(_ row: OpaquePointer) throws -> ConversationEntry {
    guard sqlite3_column_bytes(row, 2) <= Self.maximumMessageBytes else {
      throw ConversationStorageError.invalidData
    }
    var message = try decoder.decode(
      ChatMessage.self, from: VaultSQLConnection.data(row, column: 2))
    if message.completion == .streaming {
      message = message.withDelivery(.interrupted, spokenText: message.spokenText)
    }
    return .init(
      sequence: sqlite3_column_int64(row, 0), message: message,
      createdAt: Date(timeIntervalSince1970: sqlite3_column_double(row, 1)))
  }
}
