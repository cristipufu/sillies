import SilliesCore

extension VaultDatabase {
  func prepareContentSearchIndexes() throws {
    // A bounded overlap keeps phrases and identifiers searchable across storage boundaries.
    // Persist the indexed text so a later deletion always supplies FTS its exact previous input.
    try sql.execute("CREATE TABLE search_index_content(id INTEGER PRIMARY KEY,text TEXT NOT NULL)")
    try sql.execute("CREATE VIEW searchable_blocks AS SELECT id,text FROM search_index_content")
    for (table, tokenizer) in [
      ("content_search", "unicode61 remove_diacritics 2"), ("content_substrings", "trigram"),
    ] {
      try sql.execute(
        "CREATE VIRTUAL TABLE \(table) USING fts5(text, content='searchable_blocks', content_rowid='id', tokenize='\(tokenizer)')"
      )
      try sql.execute(
        """
        CREATE TRIGGER \(table)_insert AFTER INSERT ON search_index_content BEGIN
          INSERT INTO \(table)(rowid,text) VALUES(new.id,new.text);
        END
        """)
      try sql.execute(
        """
        CREATE TRIGGER \(table)_delete AFTER DELETE ON search_index_content BEGIN
          INSERT INTO \(table)(\(table),rowid,text) VALUES('delete',old.id,old.text);
        END
        """)
      try sql.execute(
        """
        CREATE TRIGGER \(table)_update AFTER UPDATE OF text ON search_index_content WHEN old.text!=new.text BEGIN
          INSERT INTO \(table)(\(table),rowid,text) VALUES('delete',old.id,old.text);
          INSERT INTO \(table)(rowid,text) VALUES(new.id,new.text);
        END
        """)
    }
    let adjacent =
      "SELECT id FROM content_blocks WHERE record_id=new.record_id AND section=new.section AND ordinal IN (new.ordinal-1,new.ordinal)"
    let refresh = """
      INSERT INTO search_index_content(id,text)
      SELECT b.id,\(Self.overlappingSearchText) FROM content_blocks b WHERE b.id IN (\(adjacent))
      ON CONFLICT(id) DO UPDATE SET text=excluded.text WHERE text!=excluded.text;
      """
    try sql.execute(
      "CREATE TRIGGER block_search_insert AFTER INSERT ON content_blocks WHEN new.section!='originalTranscript' BEGIN \(refresh) END"
    )
    try sql.execute(
      "CREATE TRIGGER block_search_update AFTER UPDATE OF text ON content_blocks WHEN new.section!='originalTranscript' BEGIN \(refresh) END"
    )
    try sql.execute(
      "CREATE TRIGGER block_search_delete AFTER DELETE ON content_blocks BEGIN DELETE FROM search_index_content WHERE id=old.id; END"
    )
  }

  private static var overlappingSearchText: String {
    "b.text||coalesce((SELECT substr(n.text,1,\(VaultTextSearchPlan.maximumQueryScalars)) FROM content_blocks n WHERE n.record_id=b.record_id AND n.section=b.section AND n.ordinal=b.ordinal+1),'')"
  }

  func refreshSearchBoundary(_ location: VaultBlockLocation) throws {
    guard location.ordinal >= 0 else { return }
    try sql.execute(
      """
      INSERT INTO search_index_content(id,text)
      SELECT b.id,\(Self.overlappingSearchText) FROM content_blocks b
      WHERE b.record_id=? AND b.section=? AND b.ordinal=? AND b.section!='originalTranscript'
      ON CONFLICT(id) DO UPDATE SET text=excluded.text WHERE text!=excluded.text
      """,
      [
        .text(location.recordID.uuidString), .text(location.section.rawValue),
        .integer(Int64(location.ordinal)),
      ])
  }
}
