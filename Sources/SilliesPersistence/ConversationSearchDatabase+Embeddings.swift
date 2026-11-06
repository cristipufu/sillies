import Foundation
import SilliesCore

extension ConversationSearchDatabase {
  public func semanticMemories(
    _ query: CompanionMemoryQuery, embedding: SearchEmbedding, provider: String
  ) throws -> [CompanionMemory] {
    try sql.cancellableRead {
      guard
        try sql.integer(
          "SELECT COUNT(*) FROM conversations WHERE id=? AND generation=?",
          [.text(query.handle.companionID), .text(query.handle.generation.uuidString)]) == 1
      else { throw ConversationStorageError.changed }
      let vectorQuery = SearchVectorQuery(embedding)
      var ranking = SearchVectorRanking(limit: query.limit)
      // Stream vector rows and retain only the requested identities. Bodies are decoded afterward.
      try sql.rows(
        """
        SELECT id,vector FROM memory_embeddings WHERE owner=? AND provider=? AND space=?
        """, [.text(query.handle.companionID), .text(provider), .text(embedding.space)]
      ) { row in
        try Task.checkCancellation()
        let score = try VaultSQLConnection.withBlob(
          row, column: 1, maximumBytes: SearchVectorStorage.maximumBytes,
          consume: vectorQuery.similarity)
        try ranking.consider(score: score) { try VaultSQLConnection.text(row) }
      }
      return try ranking.identities.flatMap { id in
        try CompanionMemoryRows.read(
          from: sql,
          statement: "SELECT body FROM companion_memories WHERE owner=? AND id=?",
          values: [.text(query.handle.companionID), .text(id)])
      }
    }
  }
}
