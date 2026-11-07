import Foundation

extension VaultDatabase {
  /// Version-two vectors are derived data. Rebuild them from the independently editable sections.
  func prepareBlockSemanticSchema() throws {
    for trigger in ["record_passage_delete", "passage_delete"] {
      try sql.execute("DROP TRIGGER \(trigger)")
    }
    for table in ["passage_vectors", "passages", "passage_sources"] {
      try sql.execute("DROP TABLE \(table)")
    }
    try sql.execute(
      """
      CREATE TABLE passage_sources(block_id INTEGER PRIMARY KEY,record_id TEXT NOT NULL,
        revision TEXT NOT NULL,next_offset INTEGER NOT NULL DEFAULT 0)
      """)
    try sql.execute(
      """
      CREATE TABLE passages(id INTEGER PRIMARY KEY AUTOINCREMENT,block_id INTEGER NOT NULL,
        record_id TEXT NOT NULL,revision TEXT NOT NULL,source_offset INTEGER NOT NULL,text TEXT NOT NULL,
        UNIQUE(block_id,source_offset))
      """)
    try sql.execute("CREATE INDEX passage_record ON passages(record_id,id)")
    try sql.execute(
      """
      CREATE TABLE passage_vectors(passage_id INTEGER NOT NULL,provider TEXT NOT NULL,
        space TEXT NOT NULL,vector BLOB NOT NULL,PRIMARY KEY(passage_id,provider))
      """)
    try sql.execute(
      "CREATE INDEX passage_vector_scope ON passage_vectors(provider,space,passage_id)")
    try sql.execute(
      "CREATE TABLE embedding_cursors(provider TEXT PRIMARY KEY,position INTEGER NOT NULL DEFAULT 0,epoch TEXT NOT NULL DEFAULT (lower(hex(randomblob(16)))))"
    )
    try sql.execute(
      "CREATE TABLE embedding_counts(provider TEXT PRIMARY KEY,processed INTEGER NOT NULL,searchable INTEGER NOT NULL)"
    )
    try sql.execute(
      "CREATE TABLE embedding_spaces(provider TEXT NOT NULL,space TEXT NOT NULL,dimensions INTEGER NOT NULL,total INTEGER NOT NULL,PRIMARY KEY(provider,space))"
    )
    try sql.execute(
      "CREATE TABLE semantic_counts(id INTEGER PRIMARY KEY CHECK(id=1),passages INTEGER NOT NULL,sources INTEGER NOT NULL)"
    )
    try sql.execute("INSERT INTO semantic_counts VALUES(1,0,0)")
    try sql.execute(
      """
      CREATE TABLE vector_changes(sequence INTEGER PRIMARY KEY AUTOINCREMENT,provider TEXT NOT NULL,
        space TEXT NOT NULL,passage_id INTEGER NOT NULL,operation TEXT NOT NULL)
      """)
    try sql.execute(
      "CREATE INDEX vector_change_provider ON vector_changes(provider,space,sequence)")
    try sql.execute(
      """
      CREATE TRIGGER block_passage_insert AFTER INSERT ON content_blocks WHEN new.section!='originalTranscript' BEGIN
        INSERT INTO passage_sources(block_id,record_id,revision) VALUES(new.id,new.record_id,lower(hex(randomblob(16))));
      END
      """)
    try sql.execute(
      """
      CREATE TRIGGER block_passage_delete AFTER DELETE ON content_blocks BEGIN
        DELETE FROM passages WHERE block_id=old.id;
        DELETE FROM passage_sources WHERE block_id=old.id;
      END
      """)
    try sql.execute(
      """
      CREATE TRIGGER block_passage_update AFTER UPDATE OF text ON content_blocks WHEN new.section!='originalTranscript' BEGIN
        DELETE FROM passages WHERE block_id=old.id;
        DELETE FROM passage_sources WHERE block_id=old.id;
        INSERT INTO passage_sources(block_id,record_id,revision) VALUES(new.id,new.record_id,lower(hex(randomblob(16))));
      END
      """)
    try sql.execute(
      """
      CREATE TRIGGER passage_source_insert AFTER INSERT ON passage_sources BEGIN
        UPDATE semantic_counts SET sources=sources+1;
      END
      """)
    try sql.execute(
      """
      CREATE TRIGGER passage_source_delete AFTER DELETE ON passage_sources BEGIN
        UPDATE semantic_counts SET sources=sources-1;
      END
      """)
    try sql.execute(
      """
      CREATE TRIGGER passage_insert AFTER INSERT ON passages BEGIN
        UPDATE semantic_counts SET passages=passages+1;
      END
      """)
    try sql.execute(
      """
      CREATE TRIGGER passage_delete AFTER DELETE ON passages BEGIN
        DELETE FROM passage_vectors WHERE passage_id=old.id;
        UPDATE semantic_counts SET passages=passages-1;
      END
      """)
    try sql.execute(
      """
      CREATE TRIGGER vector_insert AFTER INSERT ON passage_vectors BEGIN
        INSERT INTO embedding_counts VALUES(new.provider,1,new.space!='')
          ON CONFLICT(provider) DO UPDATE SET processed=processed+1,searchable=searchable+(new.space!='');
        INSERT INTO embedding_spaces VALUES(new.provider,new.space,length(new.vector)/4,1)
          ON CONFLICT(provider,space) DO UPDATE SET total=total+1;
        INSERT INTO vector_changes(provider,space,passage_id,operation) VALUES(new.provider,new.space,new.passage_id,'upsert');
      END
      """)
    try sql.execute(
      """
      CREATE TRIGGER vector_delete AFTER DELETE ON passage_vectors BEGIN
        UPDATE embedding_counts SET processed=processed-1,searchable=searchable-(old.space!='') WHERE provider=old.provider;
        UPDATE embedding_spaces SET total=total-1 WHERE provider=old.provider AND space=old.space;
        INSERT INTO vector_changes(provider,space,passage_id,operation) VALUES(old.provider,old.space,old.passage_id,'delete');
      END
      """)
  }
}
