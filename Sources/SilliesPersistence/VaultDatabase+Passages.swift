import Foundation
import SilliesCore

extension VaultDatabase {
  /// Reads one slice from the indexed document; never decodes its record body.
  public func pendingPassage() throws -> VaultPassage? {
    try sql.cancellableRead {
      var passage: VaultPassage?
      try sql.rows(
        """
        SELECT s.record_id,s.revision,CAST(s.next_offset AS TEXT),
          substr(d.body,s.next_offset+1,?)
        FROM passage_sources s JOIN documents d ON d.rowid=s.document_rowid
        WHERE s.complete=0 ORDER BY s.next_offset,s.record_id LIMIT 1
        """, [.integer(Int64(VaultPassage.maximumScalars + 1))]
      ) { row in
        guard let id = UUID(uuidString: try VaultSQLConnection.text(row)),
          let offset = Int(try VaultSQLConnection.text(row, column: 2)), offset >= 0
        else { throw CocoaError(.fileReadCorruptFile) }
        let slice = try VaultSQLConnection.text(row, column: 3)
        passage = .init(
          recordID: id, revision: try VaultSQLConnection.text(row, column: 1), offset: offset,
          text: String(slice.unicodeScalars.prefix(VaultPassage.maximumScalars)),
          isLast: slice.unicodeScalars.count <= VaultPassage.maximumScalars)
      }
      return passage
    }
  }

  @discardableResult public func savePassage(_ passage: VaultPassage) throws -> Bool {
    guard let nextOffset = passage.nextOffset else { throw CocoaError(.fileReadCorruptFile) }
    return try sql.transaction {
      let identity: [VaultSQLConnection.Value] = [
        .text(passage.recordID.uuidString), .text(passage.revision),
        .integer(Int64(passage.offset)),
      ]
      guard
        try sql.integer(
          """
          SELECT COUNT(*) FROM passage_sources WHERE record_id=? AND revision=? AND next_offset=? AND complete=0
          """, identity) == 1
      else { return false }
      try sql.execute(
        """
        INSERT INTO passages(record_id,revision,source_offset,text) VALUES(?,?,?,?)
        """, identity + [.text(passage.text)])
      try sql.execute(
        """
        UPDATE passage_sources SET next_offset=?,complete=? WHERE record_id=? AND revision=?
        """,
        [.integer(Int64(nextOffset)), .integer(passage.isLast ? 1 : 0)] + Array(identity.prefix(2)))
      return true
    }
  }

  public func pendingVaultEmbedding(provider: String) throws -> VaultEmbeddingItem? {
    try sql.cancellableRead {
      var item: VaultEmbeddingItem?
      try sql.rows(
        """
        SELECT CAST(p.id AS TEXT),p.revision,p.text FROM passages p
        LEFT JOIN passage_vectors v ON v.passage_id=p.id AND v.provider=?
        WHERE v.passage_id IS NULL ORDER BY p.id LIMIT 1
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
      guard
        try sql.integer(
          "SELECT COUNT(*) FROM passages WHERE id=? AND revision=?",
          [.text(item.id), .text(item.revision)]) == 1
      else { return false }
      try sql.execute(
        """
        INSERT INTO passage_vectors(passage_id,provider,space,vector) VALUES(?,?,?,?)
        ON CONFLICT(passage_id,provider) DO UPDATE SET space=excluded.space,vector=excluded.vector
        """,
        [
          .text(item.id), .text(provider), .text(embedding?.space ?? ""),
          .data(embedding.map { SearchVectorStorage.encode($0.values) } ?? Data([0])),
        ])
      return true
    }
  }

  public func vaultIndexProgress(provider: String) throws -> SearchIndexProgress {
    try .init(
      processed: sql.integer(
        "SELECT COUNT(*) FROM passage_vectors WHERE provider=?", [.text(provider)]),
      searchable: sql.integer(
        "SELECT COUNT(*) FROM passage_vectors WHERE provider=? AND space!=''", [.text(provider)]),
      total: sql.integer("SELECT COUNT(*) FROM passages")
        + sql.integer("SELECT COUNT(*) FROM passage_sources WHERE complete=0"))
  }

  public func removeVaultEmbeddings(except provider: String) throws {
    try sql.execute("DELETE FROM passage_vectors WHERE provider!=?", [.text(provider)])
  }
  public func resetVaultEmbeddings(provider: String) throws {
    try sql.execute("DELETE FROM passage_vectors WHERE provider=?", [.text(provider)])
  }
}
