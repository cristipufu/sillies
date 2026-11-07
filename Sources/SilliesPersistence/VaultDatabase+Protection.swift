import Foundation
import SilliesCore

extension VaultDatabase {
  /// Protection is metadata. The source body is preserved, and explicit reads overlay this column.
  public func setProtection(_ protection: VaultRecordProtection, for id: UUID) throws -> Bool {
    try sql.transaction {
      guard try isRecordAvailable(id) else { return false }
      let kept = protection == .protected
      try sql.execute(
        """
        UPDATE records SET protected=?,
          header=CAST(json_set(CAST(header AS TEXT),'$.isProtected',json(?)) AS BLOB)
        WHERE id=?
        """, [.integer(kept ? 1 : 0), .text(kept ? "true" : "false"), .text(id.uuidString)])
      try enqueueRetentionIfNeeded()
      return true
    }
  }
}
