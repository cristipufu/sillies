import Foundation

extension VaultDatabase {
  func preparePassageSchema() throws {
    try sql.transaction {
      try sql.execute(
        """
        CREATE TABLE passage_sources(record_id TEXT PRIMARY KEY, revision TEXT NOT NULL, document_rowid INTEGER NOT NULL,
          next_offset INTEGER NOT NULL DEFAULT 0, complete INTEGER NOT NULL DEFAULT 0)
        """)
      try sql.execute(
        """
        CREATE TABLE passages(id INTEGER PRIMARY KEY, record_id TEXT NOT NULL,
          revision TEXT NOT NULL, source_offset INTEGER NOT NULL, text TEXT NOT NULL,
          UNIQUE(record_id,source_offset))
        """)
      try sql.execute(
        """
        CREATE TABLE passage_vectors(passage_id INTEGER NOT NULL, provider TEXT NOT NULL,
          space TEXT NOT NULL, vector BLOB NOT NULL, PRIMARY KEY(passage_id,provider))
        """)
      try sql.execute("CREATE INDEX passage_vector_scope ON passage_vectors(provider,space)")
      try sql.execute(
        "CREATE INDEX passage_pending_sources ON passage_sources(complete,next_offset,record_id)")
      try sql.execute(
        """
        CREATE TRIGGER passage_delete AFTER DELETE ON passages BEGIN
          DELETE FROM passage_vectors WHERE passage_id=old.id;
        END
        """)
      try sql.execute(
        """
        CREATE TRIGGER record_passage_delete AFTER DELETE ON records BEGIN
          DELETE FROM passages WHERE record_id=old.id;
          DELETE FROM passage_sources WHERE record_id=old.id;
        END
        """)
      try sql.execute(
        """
        INSERT INTO passage_sources(record_id,revision,document_rowid)
        SELECT r.id,lower(hex(randomblob(16))),d.rowid FROM records r JOIN documents d ON d.id=r.id
        """)
      try sql.execute("PRAGMA user_version=2")
    }
  }

  func invalidatePassages(for id: UUID, documentRowID: Int) throws {
    try sql.execute("DELETE FROM passages WHERE record_id=?", [.text(id.uuidString)])
    try sql.execute(
      """
      INSERT INTO passage_sources(record_id,revision,document_rowid) VALUES(?,?,?)
      ON CONFLICT(record_id) DO UPDATE SET revision=excluded.revision,document_rowid=excluded.document_rowid,next_offset=0,complete=0
      """, [.text(id.uuidString), .text(UUID().uuidString), .integer(Int64(documentRowID))])
  }
}
