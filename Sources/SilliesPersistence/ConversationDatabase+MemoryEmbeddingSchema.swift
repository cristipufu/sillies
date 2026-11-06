import SilliesCore

// Called inside the conversation schema transaction; failures leave the prior index intact.
extension ConversationDatabase {
  func prepareMemoryRanking() throws {
    // This derived index owns its scope, avoiding a random body-table lookup for every vector.
    try sql.execute(
      """
      CREATE TABLE memory_embeddings_ranked(provider TEXT NOT NULL,id TEXT NOT NULL,
        owner TEXT NOT NULL,space TEXT NOT NULL,vector BLOB NOT NULL,PRIMARY KEY(provider,id))
      """)
    try sql.execute(
      """
      INSERT INTO memory_embeddings_ranked(provider,id,owner,space,vector)
      SELECT e.provider,e.id,m.owner,e.space,e.vector FROM memory_embeddings e
      JOIN companion_memories m ON m.id=e.id
      """)
    guard
      try sql.integer("SELECT COUNT(*) FROM memory_embeddings_ranked")
        == sql.integer("SELECT COUNT(*) FROM memory_embeddings")
    else { throw ConversationStorageError.invalidData }
    try sql.execute("DROP TRIGGER memory_embeddings_update")
    try sql.execute("DROP TRIGGER memory_embeddings_delete")
    try sql.execute("DROP TABLE memory_embeddings")
    try sql.execute("ALTER TABLE memory_embeddings_ranked RENAME TO memory_embeddings")
    try sql.execute("CREATE INDEX memory_embeddings_identity ON memory_embeddings(id)")
    try sql.execute(
      "CREATE INDEX memory_embeddings_scope ON memory_embeddings(owner,provider,space)")
    try prepareEmbeddingInvalidation()
    try sql.execute("PRAGMA user_version=4")
  }

  func prepareSearchEmbeddings() throws {
    try sql.execute(
      """
      CREATE TABLE memory_embeddings(provider TEXT NOT NULL,id TEXT NOT NULL,
        space TEXT NOT NULL,vector BLOB NOT NULL,PRIMARY KEY(provider,id))
      """)
    try sql.execute("CREATE INDEX memory_embeddings_identity ON memory_embeddings(id)")
    try prepareEmbeddingInvalidation()
    try sql.execute("PRAGMA user_version=3")
  }

  private func prepareEmbeddingInvalidation() throws {
    // Invalidation belongs to the same transaction as every mutation, including undo and clear.
    for event in ["UPDATE", "DELETE"] {
      try sql.execute(
        """
        CREATE TRIGGER memory_embeddings_\(event.lowercased()) AFTER \(event) ON companion_memories
        BEGIN DELETE FROM memory_embeddings WHERE id=old.id; END
        """)
    }
  }

}
