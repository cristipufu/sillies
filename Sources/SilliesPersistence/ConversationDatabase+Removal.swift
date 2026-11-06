import Foundation
import SilliesCore

extension ConversationDatabase {
  public func removeConversationData(_ removal: ConversationDataRemoval, handle: ConversationHandle)
    throws -> ConversationSnapshot
  {
    try sql.transaction {
      try validate(handle)
      var checkpoint = try savedCheckpoint(handle)
      switch removal {
      case .messages: try removeMessages(owner: handle.companionID)
      case .learnedMemories: try removeLearnedMemories(owner: handle.companionID)
      case .messagesAndMemories:
        try removeMessages(owner: handle.companionID)
        try removeLearnedMemories(owner: handle.companionID)
      }
      if removal == .learnedMemories {
        checkpoint.replaceMemory(.init())
      } else {
        checkpoint = .init(language: checkpoint.language)
      }
      try sql.execute(
        "UPDATE conversations SET generation=?,checkpoint=? WHERE id=?",
        [
          .text(UUID().uuidString), .data(try encoder.encode(checkpoint)),
          .text(handle.companionID),
        ])
    }
    return try snapshot(handle.companionID)
  }

  private func removeMessages(owner: String) throws {
    try sql.execute("DELETE FROM conversation_search WHERE owner=?", [.text(owner)])
    try sql.execute("DELETE FROM conversation_messages WHERE owner=?", [.text(owner)])
    try sql.execute("UPDATE conversations SET updated=0 WHERE id=?", [.text(owner)])
  }

  private func removeLearnedMemories(owner: String) throws {
    try sql.execute(
      "DELETE FROM memory_search WHERE id IN (SELECT id FROM companion_memories WHERE owner=?)",
      [.text(owner)])
    try sql.execute("DELETE FROM companion_memories WHERE owner=?", [.text(owner)])
    try sql.execute("DELETE FROM memory_changes WHERE owner=?", [.text(owner)])
  }
}
