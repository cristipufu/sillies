extension VaultDatabase {
  func prepareCleanupSchema() throws {
    try sql.execute("CREATE TABLE pending_deletions(record_id TEXT PRIMARY KEY)")
    try sql.execute(
      """
      CREATE TABLE vault_cleanup(kind TEXT PRIMARY KEY CHECK(kind IN ('all','retention','trash')),
        through_sequence INTEGER NOT NULL, before_date REAL NOT NULL DEFAULT 0,
        before_id TEXT NOT NULL DEFAULT '')
      """)
    try sql.execute(
      "CREATE TABLE cleanup_policy(id INTEGER PRIMARY KEY CHECK(id=1), retention_limit INTEGER, removed INTEGER NOT NULL DEFAULT 0)"
    )
    try sql.execute("INSERT INTO cleanup_policy VALUES(1,NULL,0)")
    try sql.execute("CREATE INDEX content_blocks_record ON content_blocks(record_id,id)")
    // Pending cleanup counts inspect only visibility metadata, never source-body pages.
    try sql.execute(
      "CREATE INDEX records_visibility ON records(sequence,id,created,kind,protected)")
    try sql.execute(
      """
      CREATE INDEX records_retention ON records(created DESC,id DESC,sequence)
        WHERE kind!='stash' AND protected=0
      """)
    try sql.execute(
      """
      CREATE VIEW available_records AS SELECT r.* FROM records r
      WHERE r.sequence>\(VaultCleanupSelection.visibleSequenceBoundary)
        AND NOT EXISTS(SELECT 1 FROM pending_deletions WHERE record_id=r.id)
        AND \(VaultCleanupSelection.retention.exclusion)
        AND \(VaultCleanupSelection.trash.exclusion)
      """)
    try sql.execute(
      """
      CREATE TRIGGER record_pending_delete AFTER DELETE ON records BEGIN
        DELETE FROM pending_deletions WHERE record_id=old.id;
      END
      """)
  }
}
