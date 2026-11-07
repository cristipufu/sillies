import Foundation
import SilliesCore

extension VaultDatabase {
  /// Reads one revision-owned block slice; never decodes its record body.
  public func pendingPassage() throws -> VaultPassage? {
    try sql.cancellableRead {
      var passage: VaultPassage?
      try sql.rows(
        """
        SELECT s.record_id,s.revision,CAST(s.next_offset AS TEXT),
          substr(b.text,s.next_offset+1,?),s.block_id
        FROM passage_sources s JOIN content_blocks b ON b.id=s.block_id
        JOIN available_records r ON r.id=s.record_id
        ORDER BY s.block_id LIMIT 1
        """, [.integer(Int64(VaultPassage.maximumScalars + 1))]
      ) { row in
        guard let id = UUID(uuidString: try VaultSQLConnection.text(row)),
          let offset = Int(try VaultSQLConnection.text(row, column: 2)), offset >= 0,
          let block = Int64(try VaultSQLConnection.text(row, column: 4)), block > 0
        else { throw CocoaError(.fileReadCorruptFile) }
        let slice = try VaultSQLConnection.text(row, column: 3)
        passage = .init(
          recordID: id, revision: try VaultSQLConnection.text(row, column: 1), offset: offset,
          text: String(slice.unicodeScalars.prefix(VaultPassage.maximumScalars)),
          isLast: slice.unicodeScalars.count <= VaultPassage.maximumScalars, blockID: block)
      }
      return passage
    }
  }

  @discardableResult public func savePassage(_ passage: VaultPassage) throws -> Bool {
    guard let nextOffset = passage.nextOffset, passage.blockID > 0 else {
      throw CocoaError(.fileReadCorruptFile)
    }
    guard try isRecordAvailable(passage.recordID) else { return false }
    return try sql.transaction {
      let identity: [VaultSQLConnection.Value] = [
        .integer(passage.blockID), .text(passage.revision),
        .integer(Int64(passage.offset)),
      ]
      guard
        try sql.integer(
          """
          SELECT COUNT(*) FROM passage_sources WHERE block_id=? AND revision=? AND next_offset=? AND record_id=?
          """, identity + [.text(passage.recordID.uuidString)]) == 1
      else { return false }
      try sql.execute(
        """
        INSERT INTO passages(block_id,revision,source_offset,text,record_id) VALUES(?,?,?,?,?)
        """, identity + [.text(passage.text), .text(passage.recordID.uuidString)])
      if passage.isLast {
        try sql.execute(
          "DELETE FROM passage_sources WHERE block_id=? AND revision=?", Array(identity.prefix(2)))
      } else {
        try sql.execute(
          "UPDATE passage_sources SET next_offset=? WHERE block_id=? AND revision=?",
          [.integer(Int64(nextOffset))] + Array(identity.prefix(2)))
      }
      return true
    }
  }

  public func pendingVaultEmbedding(provider: String) throws -> VaultEmbeddingItem? {
    try sql.cancellableRead {
      var item: VaultEmbeddingItem?
      try sql.rows(
        """
        SELECT CAST(p.id AS TEXT),p.revision,p.text FROM passages p
        JOIN available_records r ON r.id=p.record_id
        WHERE p.id>coalesce((SELECT position FROM embedding_cursors WHERE provider=?),0)
        ORDER BY p.id LIMIT 1
        """, [.text(provider)]
      ) { row in
        item = .init(
          id: try VaultSQLConnection.text(row),
          revision: try VaultSQLConnection.text(row, column: 1),
          text: try VaultSQLConnection.text(row, column: 2))
      }
      return item
    }
  }

  @discardableResult public func saveVaultEmbedding(
    _ embedding: SearchEmbedding?, for item: VaultEmbeddingItem, provider: String
  ) throws -> Bool {
    try sql.transaction {
      guard !provider.isEmpty, provider.utf8.count <= 1_024 else {
        throw SearchEmbeddingError.invalidVector
      }
      if let embedding {
        let dimensions = try sql.integer(
          "SELECT coalesce((SELECT dimensions FROM embedding_spaces WHERE provider=? AND space=?),?)",
          [.text(provider), .text(embedding.space), .integer(Int64(embedding.values.count))])
        guard dimensions == embedding.values.count else { throw SearchEmbeddingError.invalidVector }
      }
      guard let id = Int64(item.id), id > 0 else { throw CocoaError(.fileReadCorruptFile) }
      guard try pendingVaultEmbedding(provider: provider)?.id == item.id else { return false }
      guard
        try sql.integer(
          "SELECT COUNT(*) FROM passages WHERE id=? AND revision=?",
          [.text(item.id), .text(item.revision)]) == 1
      else { return false }
      try sql.execute(
        """
        INSERT INTO passage_vectors(passage_id,provider,space,vector) VALUES(?,?,?,?)
        """,
        [
          .text(item.id), .text(provider), .text(embedding?.space ?? ""),
          .data(embedding.map { SearchVectorStorage.encode($0.values) } ?? Data([0])),
        ])
      try sql.execute(
        "INSERT INTO embedding_cursors(provider,position) VALUES(?,?) ON CONFLICT(provider) DO UPDATE SET position=excluded.position",
        [.text(provider), .integer(id)])
      return true
    }
  }

  public func vaultIndexProgress(provider: String) throws -> SearchIndexProgress {
    try .init(
      processed: sql.integer(
        "SELECT coalesce((SELECT processed FROM embedding_counts WHERE provider=?),0)",
        [.text(provider)]),
      searchable: sql.integer(
        "SELECT coalesce((SELECT searchable FROM embedding_counts WHERE provider=?),0)",
        [.text(provider)]),
      total: sql.integer("SELECT passages+sources FROM semantic_counts WHERE id=1"))
  }

  public func removeVaultEmbeddings(except provider: String) throws {
    try sql.execute("DELETE FROM passage_vectors WHERE provider!=?", [.text(provider)])
    try sql.execute("DELETE FROM embedding_cursors WHERE provider!=?", [.text(provider)])
  }
  public func resetVaultEmbeddings(provider: String) throws {
    try sql.execute("DELETE FROM passage_vectors WHERE provider=?", [.text(provider)])
    try sql.execute("DELETE FROM embedding_cursors WHERE provider=?", [.text(provider)])
  }

  public func pruneVectorChanges() throws {
    let retainedChanges: Int64 = 100_000
    try sql.execute(
      "DELETE FROM vector_changes WHERE sequence<(SELECT coalesce(max(sequence),0) FROM vector_changes)-?",
      [.integer(retainedChanges)])
  }
}
