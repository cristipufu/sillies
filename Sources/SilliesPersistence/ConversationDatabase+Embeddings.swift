import Foundation
import SilliesCore

extension ConversationDatabase {
  public static let defaultEmbeddingBatchCount = 24
  private static let maximumEmbeddingBatchCount = 100
  public func pendingMemoryEmbeddings(
    provider: String, limit: Int = ConversationDatabase.defaultEmbeddingBatchCount
  ) throws -> [MemoryIndexItem] {
    try sql.cancellableRead {
      var result: [MemoryIndexItem] = []
      try sql.rows(
        """
        SELECT m.owner,m.body FROM companion_memories m
        LEFT JOIN memory_embeddings e ON e.id=m.id AND e.provider=?
        WHERE e.id IS NULL ORDER BY m.rowid LIMIT ?
        """,
        [.text(provider), .integer(Int64(min(Self.maximumEmbeddingBatchCount, max(1, limit))))]
      ) { row in
        result.append(
          try .init(
            owner: VaultSQLConnection.text(row),
            memory: decoder.decode(
              CompanionMemory.self,
              from: VaultSQLConnection.data(
                row, column: 1, maximumBytes: Self.maximumMemoryPayloadBytes))))
      }
      return result
    }
  }

  /// Refuse embeddings computed before a correction, deletion, history reset or undo.
  @discardableResult public func saveMemoryEmbedding(
    _ embedding: MemoryEmbedding?, for item: MemoryIndexItem, provider: String
  ) throws -> Bool {
    try sql.transaction {
      let current = try CompanionMemoryRows.read(
        from: sql,
        statement: "SELECT body FROM companion_memories WHERE owner=? AND id=?",
        values: [.text(item.owner), .text(item.memory.id.uuidString)]
      ).first
      guard current?.revision == item.memory.revision else { return false }
      let vector = embedding.map { MemoryVectorStorage.encode($0.values) } ?? Data([0])
      try sql.execute(
        """
        INSERT INTO memory_embeddings(provider,id,owner,space,vector) VALUES(?,?,?,?,?)
        ON CONFLICT(provider,id) DO UPDATE SET owner=excluded.owner,space=excluded.space,vector=excluded.vector
        """,
        [
          .text(provider), .text(item.memory.id.uuidString), .text(item.owner),
          .text(embedding?.space ?? ""), .data(vector),
        ])
      return true
    }
  }

  public func memoryIndexProgress(provider: String) throws -> MemoryIndexProgress {
    try .init(
      processed: sql.integer(
        "SELECT COUNT(*) FROM memory_embeddings WHERE provider=?", [.text(provider)]),
      searchable: sql.integer(
        "SELECT COUNT(*) FROM memory_embeddings WHERE provider=? AND space!=''", [.text(provider)]),
      total: sql.integer("SELECT COUNT(*) FROM companion_memories"))
  }

  public func removeMemoryEmbeddings(except provider: String) throws {
    try sql.execute("DELETE FROM memory_embeddings WHERE provider!=?", [.text(provider)])
  }
  public func resetMemoryEmbeddings(provider: String) throws {
    try sql.execute("DELETE FROM memory_embeddings WHERE provider=?", [.text(provider)])
  }
}
