extension VaultDatabase {
  /// Relevance filtering must not fetch source-body pages for every matching document.
  /// The ordinary view remains free to choose indexes appropriate to detail and date reads.
  func prepareSearchMetadataSchema() throws {
    try sql.transaction {
      try sql.execute(
        "CREATE INDEX records_search_metadata ON records(id,sequence,created,kind,protected,modified,image)"
      )
      try sql.execute(
        """
        CREATE VIEW available_search_records AS
        SELECT r.* FROM records r INDEXED BY records_search_metadata
        WHERE \(VaultCleanupSelection.recordVisibility)
        """)
      try sql.execute(
        """
        CREATE INDEX records_backup_files ON records(id,image,audio)
        WHERE image IS NOT NULL OR audio IS NOT NULL
        """)
      try sql.execute("PRAGMA user_version=4")
      try sql.execute(
        """
        CREATE INDEX workspace_backup_previews ON workspace(record_id,preview_image)
        WHERE preview_image IS NOT NULL
        """)
    }
  }
}
