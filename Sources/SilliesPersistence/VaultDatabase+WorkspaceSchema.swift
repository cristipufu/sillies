import Foundation

extension VaultDatabase {
  /// Source bodies remain available while the resumable section backfill prepares old captures.
  func prepareWorkspaceSchema() throws {
    try sql.transaction {
      try prepareDocumentIdentities()
      try prepareWorkspaceTables()
      try prepareContentTables()
      try prepareBlockSemanticSchema()
      try prepareMetadataDraftSchema()
      try prepareSourceFacets()
      try prepareRecordingNavigation()
      try prepareFileReferences()
      try prepareLibraryCounts()
      try prepareCleanupSchema()
      try sql.execute("PRAGMA user_version=3")
    }
  }

  private func prepareDocumentIdentities() throws {
    try sql.execute(
      "CREATE TABLE document_identities(record_id TEXT PRIMARY KEY, document_rowid INTEGER NOT NULL UNIQUE, content_hash BLOB)"
    )
    try sql.execute(
      "INSERT INTO document_identities(record_id,document_rowid) SELECT id,rowid FROM documents")
    try sql.execute(
      """
      CREATE TRIGGER record_document_delete BEFORE DELETE ON records BEGIN
        DELETE FROM documents WHERE rowid=(SELECT document_rowid FROM document_identities WHERE record_id=old.id);
        DELETE FROM document_identities WHERE record_id=old.id;
      END
      """)
  }

  private func prepareWorkspaceTables() throws {
    try sql.execute("ALTER TABLE records ADD COLUMN modified REAL")
    try sql.execute(
      "CREATE INDEX records_modified ON records(coalesce(modified,created) DESC,id DESC)")
    try sql.execute(
      """
      CREATE TABLE workspace(record_id TEXT PRIMARY KEY, kind TEXT NOT NULL DEFAULT 'capture',
        title TEXT NOT NULL DEFAULT '', modified REAL NOT NULL, starred INTEGER NOT NULL DEFAULT 0,
        trashed REAL, metadata BLOB NOT NULL, preview_state TEXT, preview_image TEXT)
      """)
    try sql.execute("CREATE INDEX workspace_modified ON workspace(modified DESC,record_id DESC)")
    try sql.execute("CREATE INDEX workspace_kind ON workspace(kind,record_id)")
    try sql.execute("CREATE INDEX workspace_starred ON workspace(starred,record_id)")
    try sql.execute("CREATE INDEX workspace_trash ON workspace(trashed,record_id)")
    try sql.execute("CREATE INDEX workspace_preview ON workspace(preview_state,modified,record_id)")
    try sql.execute("CREATE INDEX workspace_preview_image ON workspace(preview_image)")
    for event in ["INSERT", "UPDATE OF modified"] {
      let name = event == "INSERT" ? "insert" : "update"
      try sql.execute(
        "CREATE TRIGGER workspace_modified_\(name) AFTER \(event) ON workspace BEGIN UPDATE records SET modified=new.modified WHERE id=new.record_id; END"
      )
    }
    try sql.execute("CREATE TABLE vault_collections(id TEXT PRIMARY KEY, name TEXT NOT NULL)")
    try sql.execute(
      "CREATE TABLE vault_collection_items(collection_id TEXT NOT NULL, record_id TEXT NOT NULL, PRIMARY KEY(collection_id,record_id))"
    )
    try sql.execute(
      "CREATE INDEX vault_collections_by_record ON vault_collection_items(record_id,collection_id)")
    try sql.execute(
      "CREATE TABLE vault_tags(tag TEXT NOT NULL, record_id TEXT NOT NULL, PRIMARY KEY(tag,record_id))"
    )
    try sql.execute("CREATE INDEX vault_tags_by_record ON vault_tags(record_id,tag)")
    try sql.execute("CREATE TABLE vault_saved_searches(id TEXT PRIMARY KEY, body BLOB NOT NULL)")
    try sql.execute(
      """
      CREATE TRIGGER record_workspace_delete AFTER DELETE ON records BEGIN
        DELETE FROM workspace WHERE record_id=old.id;
        DELETE FROM vault_collection_items WHERE record_id=old.id;
        DELETE FROM vault_tags WHERE record_id=old.id;
      END
      """)
  }

  private func prepareContentTables() throws {
    try sql.execute(
      """
      CREATE TABLE content_sections(record_id TEXT NOT NULL, section TEXT NOT NULL,
        revision TEXT NOT NULL, digest BLOB NOT NULL, user_edited INTEGER NOT NULL DEFAULT 0,
        block_count INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(record_id,section))
      """)
    try sql.execute(
      """
      CREATE TABLE content_blocks(id INTEGER PRIMARY KEY AUTOINCREMENT, record_id TEXT NOT NULL,
        section TEXT NOT NULL, ordinal INTEGER NOT NULL, text TEXT NOT NULL,
        start_seconds REAL, speaker TEXT, UNIQUE(record_id,section,ordinal))
      """)
    try sql.execute("CREATE INDEX content_block_identity ON content_blocks(id,record_id)")
    try prepareContentSearchIndexes()
    try sql.execute(
      "CREATE TABLE content_backfill(sequence INTEGER PRIMARY KEY, record_id TEXT NOT NULL UNIQUE)")
    try sql.execute("INSERT INTO content_backfill SELECT sequence,id FROM records")
    try sql.execute(
      "CREATE TABLE vault_drafts(record_id TEXT NOT NULL, section TEXT NOT NULL, body BLOB NOT NULL, PRIMARY KEY(record_id,section))"
    )
    try sql.execute(
      """
      CREATE TRIGGER record_content_delete AFTER DELETE ON records BEGIN
        DELETE FROM content_blocks WHERE record_id=old.id;
        DELETE FROM content_sections WHERE record_id=old.id;
        DELETE FROM content_backfill WHERE record_id=old.id;
        DELETE FROM vault_drafts WHERE record_id=old.id;
        DELETE FROM vault_metadata_drafts WHERE record_id=old.id;
      END
      """)
  }

  private func prepareLibraryCounts() throws {
    try sql.execute(
      "CREATE TABLE library_counts(kind TEXT PRIMARY KEY, total INTEGER NOT NULL, eligible INTEGER NOT NULL)"
    )
    try sql.execute("CREATE TABLE trash_counts(kind TEXT PRIMARY KEY,total INTEGER NOT NULL)")
    try sql.execute(
      "INSERT INTO library_counts SELECT kind,count(*),sum(kind!='stash' AND protected=0) FROM records GROUP BY kind"
    )
    try sql.execute(
      """
      CREATE TRIGGER library_count_insert AFTER INSERT ON records BEGIN
        INSERT INTO library_counts VALUES(new.kind,1,new.kind!='stash' AND new.protected=0)
          ON CONFLICT(kind) DO UPDATE SET total=total+1,eligible=eligible+(new.kind!='stash' AND new.protected=0);
      END
      """)
    try sql.execute(
      """
      CREATE TRIGGER library_count_delete BEFORE DELETE ON records BEGIN
        UPDATE trash_counts SET total=total-1 WHERE kind=old.kind AND EXISTS(SELECT 1 FROM workspace WHERE record_id=old.id AND trashed IS NOT NULL);
        UPDATE library_counts SET total=total-1,eligible=eligible-(old.kind!='stash' AND old.protected=0 AND NOT EXISTS(SELECT 1 FROM workspace WHERE record_id=old.id AND starred=1))
          WHERE kind=old.kind;
      END
      """)
    try sql.execute(
      """
      CREATE TRIGGER workspace_trash_insert AFTER INSERT ON workspace WHEN new.trashed IS NOT NULL BEGIN
        INSERT INTO trash_counts SELECT kind,1 FROM records WHERE id=new.record_id
          ON CONFLICT(kind) DO UPDATE SET total=total+1;
      END
      """)
    try sql.execute(
      """
      CREATE TRIGGER workspace_trash_update AFTER UPDATE OF trashed ON workspace WHEN (old.trashed IS NULL)!=(new.trashed IS NULL) BEGIN
        INSERT INTO trash_counts SELECT kind,(new.trashed IS NOT NULL)-(old.trashed IS NOT NULL) FROM records WHERE id=new.record_id
          ON CONFLICT(kind) DO UPDATE SET total=total+excluded.total;
      END
      """)
    try sql.execute(
      """
      CREATE TRIGGER library_count_update AFTER UPDATE OF kind,protected ON records BEGIN
        UPDATE library_counts SET total=total-1,eligible=eligible-(old.kind!='stash' AND old.protected=0 AND NOT EXISTS(SELECT 1 FROM workspace WHERE record_id=old.id AND starred=1))
          WHERE kind=old.kind;
        INSERT INTO library_counts VALUES(new.kind,1,new.kind!='stash' AND new.protected=0 AND NOT EXISTS(SELECT 1 FROM workspace WHERE record_id=new.id AND starred=1))
          ON CONFLICT(kind) DO UPDATE SET total=total+1,eligible=eligible+excluded.eligible;
      END
      """)
    try sql.execute(
      """
      CREATE TRIGGER workspace_star_insert AFTER INSERT ON workspace WHEN new.starred=1 BEGIN
        UPDATE library_counts SET eligible=eligible-1 WHERE kind=(SELECT kind FROM records WHERE id=new.record_id AND kind!='stash' AND protected=0);
      END
      """)
    try sql.execute(
      """
      CREATE TRIGGER workspace_star_update AFTER UPDATE OF starred ON workspace WHEN old.starred!=new.starred BEGIN
        UPDATE library_counts SET eligible=eligible+old.starred-new.starred WHERE kind=(SELECT kind FROM records WHERE id=new.record_id AND kind!='stash' AND protected=0);
      END
      """)
  }
}
