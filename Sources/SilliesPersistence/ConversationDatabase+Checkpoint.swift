import Foundation
import SilliesCore

extension ConversationDatabase {
  func invalidatesMemory(_ update: ConversationUpdate, memory: ConversationMemory) throws -> Bool {
    guard let through = memory.throughMessageID else { return false }
    let boundary = try sequence(of: through, owner: update.handle.companionID)
    let changed = update.removedMessageIDs.union(update.messages.map(\.id))
    for id in changed {
      if try sql.integer(
        "SELECT EXISTS(SELECT 1 FROM conversation_messages WHERE owner=? AND id=? AND sequence<=?)",
        [.text(update.handle.companionID), .text(id.uuidString), .integer(boundary)]) != 0
      {
        return true
      }
    }
    return false
  }

  public func checkpoint(_ handle: ConversationHandle) throws -> ConversationMemorySnapshot {
    try savedCheckpoint(handle).memorySnapshot
  }

  /// Serial with transcript writes. A late job cannot overwrite a newer checkpoint, draft or reset.
  public func advanceCheckpoint(_ update: ConversationMemoryUpdate) throws -> Bool {
    var committed = false
    try sql.transaction {
      var checkpoint = try savedCheckpoint(update.handle)
      guard checkpoint.memorySnapshot == update.expected else { return }
      guard let through = update.replacement.throughMessageID else {
        throw ConversationStorageError.invalidData
      }
      let next = try sequence(of: through, owner: update.handle.companionID)
      let previous =
        try update.expected.memory.throughMessageID.map {
          try sequence(of: $0, owner: update.handle.companionID)
        } ?? 0
      guard next > previous else { throw ConversationStorageError.invalidData }
      checkpoint.replaceMemory(update.replacement)
      let bytes = try encoder.encode(checkpoint)
      guard bytes.count <= Self.maximumCheckpointBytes else {
        throw ConversationStorageError.invalidData
      }
      try sql.execute(
        "UPDATE conversations SET checkpoint=? WHERE id=? AND generation=?",
        [
          .data(bytes), .text(update.handle.companionID),
          .text(update.handle.generation.uuidString),
        ])
      committed = true
    }
    return committed
  }

  func savedCheckpoint(_ handle: ConversationHandle) throws -> ConversationCheckpoint {
    try validate(handle)
    var result: ConversationCheckpoint?
    try sql.rows(
      "SELECT checkpoint FROM conversations WHERE id=?", [.text(handle.companionID)]
    ) { row in
      result = try decoder.decode(
        ConversationCheckpoint.self,
        from: VaultSQLConnection.data(row, maximumBytes: Self.maximumCheckpointBytes))
    }
    guard let result else { throw ConversationStorageError.changed }
    return result
  }
}
