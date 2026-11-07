import Foundation

extension VaultDatabase {
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
  public func backupAttachments(after sequence: Int64) throws -> (
    sequence: Int64, filenames: [String]
  )? {
    var result: (sequence: Int64, filenames: [String])?
    try sql.rows(
      """
      SELECT r.sequence,coalesce(r.image,''),coalesce(r.audio,''),coalesce(w.preview_image,'')
      FROM records r LEFT JOIN workspace w ON w.record_id=r.id
      WHERE r.sequence>? ORDER BY r.sequence LIMIT 1
      """, [.integer(sequence)]
    ) { row in
      guard let identity = Int64(try VaultSQLConnection.text(row)) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      let names = try (1...3).map { try VaultSQLConnection.text(row, column: Int32($0)) }.filter {
        !$0.isEmpty
      }
      result = (identity, names)
    }
    return result
  }
}
