import Foundation
import SilliesCore

extension ConversationDatabase {
  private static let maximumMemoryPayloadBytes = 32_768
  private static let maximumMemoryReceiptBytes = maximumMemoryPayloadBytes * 2 + 1_024
  private static let maximumMemoryKeyCharacters = 80
  private static let maximumMemoryValueCharacters = 500
  private static let maximumMemoryCount = 200
  private static let maximumRecentMemoryChanges = 40

  public func memories(_ handle: ConversationHandle, query: String) throws -> [CompanionMemory] {
    try validate(handle)
    var result: [CompanionMemory] = []
    var predicate = "owner=?"
    var values: [VaultSQLConnection.Value] = [.text(handle.companionID)]
    if !query.isEmpty {
      guard let expression = VaultSearchTerms.expression(query, matching: .anyTerm) else {
        return []
      }
      predicate += " AND id IN (SELECT id FROM memory_search WHERE memory_search MATCH ?)"
      values.append(.text(expression))
    }
    try sql.rows(
      "SELECT body FROM companion_memories WHERE \(predicate) ORDER BY updated DESC LIMIT ?",
      values + [.integer(Int64(Self.maximumMemoryCount))]
    ) { row in
      result.append(
        try decoder.decode(
          CompanionMemory.self,
          from: VaultSQLConnection.data(row, maximumBytes: Self.maximumMemoryPayloadBytes)))
    }
    return result
  }

  public func remember(_ request: MemoryWrite) throws -> MemoryReceipt {
    try sql.transaction {
      try validate(request.handle)
      try validateMemorySource(request)
      let key = request.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard !key.isEmpty, key.count <= Self.maximumMemoryKeyCharacters,
        !request.value.isEmpty, request.value.count <= Self.maximumMemoryValueCharacters
      else { throw ConversationStorageError.invalidData }
      let previous = try previousMemory(for: request, key: key)
      if previous == nil {
        guard
          try sql.integer(
            "SELECT COUNT(*) FROM companion_memories WHERE owner=?",
            [.text(request.handle.companionID)]) < Self.maximumMemoryCount
        else {
          throw ConversationStorageError.invalidData
        }
      }
      let saved = CompanionMemory(
        replacing: previous, fact: .init(key: previous?.key ?? key, value: request.value),
        source: request.source, savedAt: request.savedAt)
      try writeMemory(saved, owner: request.handle.companionID)
      let receipt = MemoryReceipt(
        handle: request.handle, id: UUID(), previous: previous, saved: saved)
      let receiptData = try encoder.encode(receipt)
      guard receiptData.count <= Self.maximumMemoryReceiptBytes else {
        throw ConversationStorageError.invalidData
      }
      try sql.execute(
        "INSERT INTO memory_changes(id,owner,body) VALUES(?,?,?)",
        [
          .text(receipt.id.uuidString), .text(request.handle.companionID),
          .data(receiptData),
        ])
      try sql.execute(
        "DELETE FROM memory_changes WHERE owner=? AND sequence NOT IN (SELECT sequence FROM memory_changes WHERE owner=? ORDER BY sequence DESC LIMIT ?)",
        [
          .text(request.handle.companionID), .text(request.handle.companionID),
          .integer(Int64(Self.maximumRecentMemoryChanges)),
        ])
      return receipt
    }
  }

  public func forget(_ handle: ConversationHandle, id: UUID) throws -> ConversationSnapshot {
    try sql.transaction {
      try validate(handle)
      try removeMemory(id, owner: handle.companionID)
      // Old undo payloads must not retain the fact after an explicit Forget action.
      try sql.execute("DELETE FROM memory_changes WHERE owner=?", [.text(handle.companionID)])
      try invalidateSummary(handle.companionID)
    }
    return try snapshot(handle.companionID)
  }

  public func undoMemory(_ handle: ConversationHandle, receiptID: UUID) throws
    -> ConversationSnapshot
  {
    try sql.transaction {
      try validate(handle)
      var receipt: MemoryReceipt?
      try sql.rows(
        "SELECT body FROM memory_changes WHERE owner=? AND id=?",
        [.text(handle.companionID), .text(receiptID.uuidString)]
      ) { row in
        receipt = try decoder.decode(
          MemoryReceipt.self,
          from: VaultSQLConnection.data(row, maximumBytes: Self.maximumMemoryReceiptBytes))
      }
      guard let receipt,
        try memory(owner: handle.companionID, identity: .key(receipt.saved.key))?.revision
          == receipt.saved.revision
      else { throw ConversationStorageError.changed }
      try removeMemory(receipt.saved.id, owner: handle.companionID)
      if let previous = receipt.previous { try writeMemory(previous, owner: handle.companionID) }
      try sql.execute(
        "DELETE FROM memory_changes WHERE owner=? AND id=?",
        [.text(handle.companionID), .text(receiptID.uuidString)])
      try invalidateSummary(handle.companionID)
    }
    return try snapshot(handle.companionID)
  }

  public func recentMemoryChanges(_ handle: ConversationHandle) throws -> [MemoryReceipt] {
    try validate(handle)
    var receipts: [MemoryReceipt] = []
    try sql.rows(
      "SELECT body FROM memory_changes WHERE owner=? ORDER BY sequence DESC LIMIT ?",
      [.text(handle.companionID), .integer(Int64(Self.maximumRecentMemoryChanges))]
    ) { row in
      receipts.append(
        try decoder.decode(
          MemoryReceipt.self,
          from: VaultSQLConnection.data(row, maximumBytes: Self.maximumMemoryReceiptBytes)))
    }
    return receipts
  }

  private func validateMemorySource(_ request: MemoryWrite) throws {
    guard !request.sourceQuote.isEmpty,
      request.sourceQuote.count <= ChatContext.maximumMessageCharacters,
      request.sourceQuote.utf8.count <= ChatContext.maximumMessageBytes
    else {
      throw ConversationStorageError.invalidData
    }
    var source: ChatMessage?
    try sql.rows(
      "SELECT body FROM conversation_messages WHERE owner=? AND id=?",
      [.text(request.handle.companionID), .text(request.sourceMessageID.uuidString)]
    ) { row in
      source = try decoder.decode(
        ChatMessage.self, from: VaultSQLConnection.data(row, maximumBytes: Self.maximumMessageBytes)
      )
    }
    guard let source, source.role == .user, source.text.contains(request.sourceQuote) else {
      throw ConversationStorageError.invalidData
    }
  }

  private func previousMemory(for request: MemoryWrite, key: String) throws -> CompanionMemory? {
    guard let target = request.replacement else {
      return try memory(owner: request.handle.companionID, identity: .key(key))
    }
    guard let previous = try memory(owner: request.handle.companionID, identity: .id(target.id)),
      previous.revision == target.revision
    else { throw MemoryMutationError.replacementChanged }
    return previous
  }

  private enum MemoryIdentity {
    case key(String)
    case id(UUID)
    var column: String {
      switch self {
      case .key: "key"
      case .id: "id"
      }
    }
    var value: String {
      switch self {
      case .key(let key): key
      case .id(let id): id.uuidString
      }
    }
  }

  private func memory(owner: String, identity: MemoryIdentity) throws -> CompanionMemory? {
    var memory: CompanionMemory?
    try sql.rows(
      "SELECT body FROM companion_memories WHERE owner=? AND \(identity.column)=?",
      [.text(owner), .text(identity.value)]
    ) { row in
      memory = try decoder.decode(
        CompanionMemory.self,
        from: VaultSQLConnection.data(row, maximumBytes: Self.maximumMemoryPayloadBytes))
    }
    return memory
  }

  private func writeMemory(_ memory: CompanionMemory, owner: String) throws {
    let data = try encoder.encode(memory)
    guard data.count <= Self.maximumMemoryPayloadBytes else {
      throw ConversationStorageError.invalidData
    }
    try sql.execute(
      "INSERT INTO companion_memories(id,owner,key,updated,body) VALUES(?,?,?,?,?) ON CONFLICT(owner,key) DO UPDATE SET updated=excluded.updated,body=excluded.body",
      [
        .text(memory.id.uuidString), .text(owner), .text(memory.key),
        .real(memory.savedAt.timeIntervalSince1970), .data(data),
      ])
    try sql.execute("DELETE FROM memory_search WHERE id=?", [.text(memory.id.uuidString)])
    try sql.execute(
      "INSERT INTO memory_search(id,text) VALUES(?,?)",
      [.text(memory.id.uuidString), .text(memory.key + " " + memory.value)])
  }

  private func removeMemory(_ id: UUID, owner: String) throws {
    try sql.execute(
      "DELETE FROM memory_search WHERE id IN (SELECT id FROM companion_memories WHERE owner=? AND id=?)",
      [.text(owner), .text(id.uuidString)])
    try sql.execute(
      "DELETE FROM companion_memories WHERE owner=? AND id=?", [.text(owner), .text(id.uuidString)])
  }

  private func invalidateSummary(_ owner: String) throws {
    var checkpoint: ConversationCheckpoint?
    try sql.rows("SELECT checkpoint FROM conversations WHERE id=?", [.text(owner)]) { row in
      checkpoint = try decoder.decode(
        ConversationCheckpoint.self,
        from: VaultSQLConnection.data(row, maximumBytes: Self.maximumCheckpointBytes))
    }
    if var checkpoint {
      checkpoint.memory = .init()
      try sql.execute(
        "UPDATE conversations SET checkpoint=?,generation=? WHERE id=?",
        [.data(try encoder.encode(checkpoint)), .text(UUID().uuidString), .text(owner)])
    }
  }
}
