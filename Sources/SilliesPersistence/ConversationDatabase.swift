import Foundation
import SilliesCore

/// Append/update individual messages. Opening or saving never decodes the whole conversation.
public final class ConversationDatabase {
  public static let filename = "conversations.sqlite"
  static let schemaVersion = 2
  static let maximumMessageBytes = 1_024 * 1_024
  static let maximumCheckpointBytes = 64 * 1_024
  private static let directoryPermissions = 0o700
  let sql: VaultSQLConnection
  let encoder = JSONEncoder()
  let decoder = JSONDecoder()

  public init(directory: URL) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: Self.directoryPermissions])
    sql = try VaultSQLConnection(url: directory.appendingPathComponent(Self.filename))
    try sql.execute("PRAGMA journal_mode=WAL")
    try sql.execute("PRAGMA synchronous=FULL")
    try sql.execute("PRAGMA secure_delete=ON")
    try prepareSchema()
  }

  public func open(_ owner: ConversationOwner) throws -> ConversationSnapshot {
    guard !owner.id.isEmpty, owner.id.utf8.count <= 256 else {
      throw ConversationStorageError.invalidData
    }
    let checkpoint = try encoder.encode(ConversationCheckpoint())
    try sql.execute(
      "INSERT INTO conversations(id,generation,name,updated,checkpoint) VALUES(?,?,?,0,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name",
      [.text(owner.id), .text(UUID().uuidString), .text(owner.name), .data(checkpoint)])
    return try snapshot(owner.id)
  }

  public func save(_ update: ConversationUpdate) throws {
    try sql.transaction {
      try validate(update.handle)
      var presentation = update.checkpoint
      presentation.preserveContext(from: try savedCheckpoint(update.handle))
      if !update.messages.isEmpty || !update.removedMessageIDs.isEmpty {
        presentation.recordHistoryChange()
      }
      if try invalidatesMemory(update, memory: presentation.memory) {
        presentation.replaceMemory(.init())
      }
      for id in update.removedMessageIDs { try removeMessage(id, owner: update.handle.companionID) }
      for message in update.messages {
        try saveMessage(message, owner: update.handle.companionID, at: update.savedAt)
      }
      let checkpoint = try encode(presentation, maximumBytes: Self.maximumCheckpointBytes)
      try sql.execute(
        "UPDATE conversations SET checkpoint=?,updated=MAX(updated,?) WHERE id=?",
        [
          .data(checkpoint), .real(update.savedAt.timeIntervalSince1970),
          .text(update.handle.companionID),
        ])
    }
  }

  public func clear(_ handle: ConversationHandle) throws -> ConversationSnapshot {
    try sql.transaction {
      try validate(handle)
      try sql.execute(
        "DELETE FROM memory_search WHERE id IN (SELECT id FROM companion_memories WHERE owner=?)",
        [.text(handle.companionID)])
      try sql.execute("DELETE FROM companion_memories WHERE owner=?", [.text(handle.companionID)])
      try sql.execute("DELETE FROM memory_changes WHERE owner=?", [.text(handle.companionID)])
      try sql.execute("DELETE FROM conversation_search WHERE owner=?", [.text(handle.companionID)])
      try sql.execute(
        "DELETE FROM conversation_messages WHERE owner=?", [.text(handle.companionID)])
      try sql.execute(
        "UPDATE conversations SET generation=?,checkpoint=?,updated=0 WHERE id=?",
        [
          .text(UUID().uuidString), .data(try encoder.encode(ConversationCheckpoint())),
          .text(handle.companionID),
        ])
    }
    return try snapshot(handle.companionID)
  }

  func validate(_ handle: ConversationHandle) throws {
    guard
      try sql.integer(
        "SELECT COUNT(*) FROM conversations WHERE id=? AND generation=?",
        [.text(handle.companionID), .text(handle.generation.uuidString)]) == 1
    else { throw ConversationStorageError.changed }
  }

  func snapshot(_ id: String) throws -> ConversationSnapshot {
    var result: (ConversationHandle, ConversationCheckpoint)?
    try sql.rows("SELECT generation,checkpoint FROM conversations WHERE id=?", [.text(id)]) { row in
      guard let generation = UUID(uuidString: try VaultSQLConnection.text(row)) else {
        throw ConversationStorageError.invalidData
      }
      let data = try VaultSQLConnection.data(
        row, column: 1, maximumBytes: Self.maximumCheckpointBytes)
      guard data.count <= Self.maximumCheckpointBytes else {
        throw ConversationStorageError.invalidData
      }
      result = (
        .init(companionID: id, generation: generation),
        try decoder.decode(ConversationCheckpoint.self, from: data)
      )
    }
    guard let (handle, checkpoint) = result else { throw ConversationStorageError.changed }
    return try .init(handle: handle, checkpoint: checkpoint, page: page(.init(handle: handle)))
  }

  private func saveMessage(_ message: ChatMessage, owner: String, at date: Date) throws {
    let data = try encode(message, maximumBytes: Self.maximumMessageBytes)
    guard
      try sql.integer(
        "SELECT COUNT(*) FROM conversation_messages WHERE id=? AND owner!=?",
        [.text(message.id.uuidString), .text(owner)]) == 0
    else { throw ConversationStorageError.invalidData }
    try sql.execute(
      "INSERT INTO conversation_messages(id,owner,created,body,preview) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET body=excluded.body,preview=excluded.preview",
      [
        .text(message.id.uuidString), .text(owner), .real(date.timeIntervalSince1970), .data(data),
        .text(String(message.text.prefix(160))),
      ])
    try sql.execute(
      "DELETE FROM conversation_search WHERE rowid=(SELECT sequence FROM conversation_messages WHERE id=?)",
      [.text(message.id.uuidString)])
    try sql.execute(
      "INSERT INTO conversation_search(rowid,id,owner,text) SELECT sequence,id,owner,? FROM conversation_messages WHERE id=?",
      [.text(message.text), .text(message.id.uuidString)])
  }

  private func removeMessage(_ id: UUID, owner: String) throws {
    try sql.execute(
      "DELETE FROM conversation_search WHERE rowid=(SELECT sequence FROM conversation_messages WHERE owner=? AND id=?)",
      [.text(owner), .text(id.uuidString)])
    try sql.execute(
      "DELETE FROM conversation_messages WHERE owner=? AND id=?",
      [.text(owner), .text(id.uuidString)])
  }

  private func encode(_ value: some Encodable, maximumBytes: Int) throws -> Data {
    let data = try encoder.encode(value)
    guard data.count <= maximumBytes else { throw ConversationStorageError.invalidData }
    return data
  }

  private func prepareSchema() throws {
    let version = try sql.integer("PRAGMA user_version")
    guard version <= Self.schemaVersion else { throw ConversationStorageError.unsupportedVersion }
    if version == 1 {
      try sql.transaction { try prepareMemoryPaging() }
      return
    }
    guard version == 0 else { return }
    try sql.transaction {
      try sql.execute(
        "CREATE TABLE conversations(id TEXT PRIMARY KEY,generation TEXT NOT NULL,name TEXT NOT NULL,updated REAL NOT NULL,checkpoint BLOB NOT NULL)"
      )
      try sql.execute(
        "CREATE TABLE conversation_messages(sequence INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT NOT NULL UNIQUE,owner TEXT NOT NULL,created REAL NOT NULL,body BLOB NOT NULL,preview TEXT NOT NULL)"
      )
      try sql.execute(
        "CREATE INDEX conversation_messages_owner ON conversation_messages(owner,sequence)")
      try sql.execute(
        "CREATE VIRTUAL TABLE conversation_search USING fts5(id UNINDEXED,owner UNINDEXED,text,tokenize='unicode61 remove_diacritics 2')"
      )
      try sql.execute("PRAGMA user_version=1")
      try sql.execute(
        "CREATE TABLE companion_memories(id TEXT NOT NULL UNIQUE,owner TEXT NOT NULL,key TEXT NOT NULL,updated REAL NOT NULL,body BLOB NOT NULL,PRIMARY KEY(owner,key))"
      )
      try sql.execute(
        "CREATE TABLE memory_changes(sequence INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT NOT NULL UNIQUE,owner TEXT NOT NULL,body BLOB NOT NULL)"
      )
      try sql.execute("CREATE INDEX memory_changes_owner ON memory_changes(owner,sequence)")
      try sql.execute(
        "CREATE VIRTUAL TABLE memory_search USING fts5(id UNINDEXED,text,tokenize='unicode61 remove_diacritics 2')"
      )
      try prepareMemoryPaging()
    }
  }

  private func prepareMemoryPaging() throws {
    try sql.execute(
      "CREATE INDEX companion_memories_recent ON companion_memories(owner,updated DESC,id DESC)")
    try sql.execute("PRAGMA user_version=2")
  }
}
