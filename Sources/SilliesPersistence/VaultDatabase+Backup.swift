import Foundation

extension VaultDatabase {
  private static let backupReferenceBatchSize = 128
  public func validateBackup() throws {
    try sql.cancellableRead {
      try sql.rows("PRAGMA quick_check") { row in
        guard try VaultSQLConnection.text(row) == "ok" else {
          throw CocoaError(.fileReadCorruptFile)
        }
      }
      _ = try page(.init())
    }
  }
  /// The snapshot's own references define the export; no filename from metadata can escape its root.
  public func backupAttachments(after recordID: UUID?) throws -> (
    lastRecordID: UUID, filenames: [String]
  )? {
    var lastRecordID: UUID?
    var filenames: Set<String> = []
    let position = VaultSQLConnection.Value.text(recordID?.uuidString ?? "")
    try sql.rows(
      backupAttachmentQuery, [position, position, .integer(Int64(Self.backupReferenceBatchSize))]
    ) { row in
      let storedID = try VaultSQLConnection.text(row)
      // The UUID cursor must preserve the database's lexical ordering exactly.
      guard let identity = UUID(uuidString: storedID), identity.uuidString == storedID else {
        throw CocoaError(.fileReadCorruptFile)
      }
      let names = try (1...3).map { try VaultSQLConnection.text(row, column: Int32($0)) }.filter {
        !$0.isEmpty
      }
      lastRecordID = identity
      filenames.formUnion(names)
    }
    return lastRecordID.map { ($0, filenames.sorted()) }
  }

  var backupAttachmentQuery: String {
    let recordIndex = supportsSearchMetadata ? "INDEXED BY records_backup_files" : ""
    let previewIndex = supportsSearchMetadata ? "INDEXED BY workspace_backup_previews" : ""
    // Merge two ordered, disjoint index streams. Keep preview owners first: reversing that join
    // scans every fileless record, even when there are no previews. No whole-library sort is needed.
    return """
      SELECT r.id AS record_id,coalesce(r.image,''),coalesce(r.audio,''),coalesce(w.preview_image,'')
      FROM records r \(recordIndex) LEFT JOIN workspace w ON w.record_id=r.id
      WHERE r.id>? AND (r.image IS NOT NULL OR r.audio IS NOT NULL)
      UNION ALL
      SELECT w.record_id AS record_id,'','',w.preview_image
      FROM workspace w \(previewIndex) CROSS JOIN records r
      WHERE w.preview_image IS NOT NULL AND w.record_id>? AND r.id=w.record_id
        AND r.image IS NULL AND r.audio IS NULL
      ORDER BY record_id LIMIT ?
      """
  }
}
