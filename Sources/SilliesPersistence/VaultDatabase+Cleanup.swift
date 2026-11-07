import Foundation
import SilliesCore

extension VaultDatabase {
  public static let cleanupRecordLimit = 100
  public static let cleanupBlockLimit = 512

  func enqueueDeletion(_ deletion: VaultDeletion) throws {
    switch deletion {
    case .all:
      try sql.execute(
        """
        INSERT INTO vault_cleanup(kind,through_sequence) SELECT 'all',coalesce(max(sequence),0) FROM records WHERE true
        ON CONFLICT(kind) DO UPDATE SET through_sequence=excluded.through_sequence
        """)
    case .records(let ids):
      for id in ids {
        try sql.execute(
          "INSERT OR IGNORE INTO pending_deletions SELECT id FROM records WHERE id=?",
          [.text(id.uuidString)])
      }
    }
  }

  /// Explicit insertion creates a fresh capture after deletion. A retired source may already
  /// be partially reclaimed, so its old section digests and workspace edits cannot be reused.
  func retireHiddenRecordForInsertion(_ id: UUID) throws {
    let identity: [VaultSQLConnection.Value] = [.text(id.uuidString)]
    guard
      try sql.integer(
        "SELECT EXISTS(SELECT 1 FROM records WHERE id=?) AND NOT EXISTS(SELECT 1 FROM available_records WHERE id=?)",
        identity + identity) != 0
    else { return }
    try stageRetiredAttachments(id: id)
    try sql.execute("DELETE FROM records WHERE id=?", identity)
  }

  public func enqueueTrashCleanup(at date: Date) throws {
    guard date.timeIntervalSince1970.isFinite else { throw VaultEditingError.invalidValue }
    try sql.transaction {
      try sql.execute(
        """
        INSERT INTO vault_cleanup(kind,through_sequence,before_date)
          SELECT 'trash',coalesce(max(sequence),0),? FROM records WHERE true
        ON CONFLICT(kind) DO UPDATE SET through_sequence=excluded.through_sequence,before_date=excluded.before_date
        """, [.real(date.timeIntervalSince1970)])
    }
  }

  func requestRetention(_ policy: VaultRetentionPolicy) throws {
    try sql.execute(
      "UPDATE cleanup_policy SET retention_limit=? WHERE id=1",
      [policy.limit.map { .integer(Int64($0)) } ?? .null])
    try enqueueRetentionIfNeeded()
  }

  func enqueueRetentionIfNeeded() throws {
    guard try sql.integer("SELECT count(*) FROM vault_cleanup WHERE kind='retention'") == 0 else {
      return
    }
    let limit = try sql.integer("SELECT coalesce(retention_limit,0) FROM cleanup_policy WHERE id=1")
    guard limit > 0 else { return }
    // Select the first excess capture, never an array of all expired identities.
    try sql.execute(
      """
      INSERT INTO vault_cleanup(kind,through_sequence,before_date,before_id)
      SELECT 'retention',(SELECT coalesce(max(sequence),0) FROM records),r.created,r.id
      FROM available_records r WHERE r.kind!='stash' AND r.protected=0
        AND NOT EXISTS(SELECT 1 FROM workspace WHERE record_id=r.id AND starred=1)
      ORDER BY r.created DESC,r.id DESC LIMIT 1 OFFSET ?
      """, [.integer(Int64(limit))])
  }

  public func cleanupProgress() throws -> VaultCleanupProgress {
    try .init(
      isPending: sql.integer(
        "SELECT EXISTS(SELECT 1 FROM vault_cleanup) OR EXISTS(SELECT 1 FROM pending_deletions) OR EXISTS(SELECT 1 FROM attachment_cleanup)"
      ) != 0,
      removedRecords: sql.integer("SELECT removed FROM cleanup_policy WHERE id=1"))
  }

  /// The sequence index can prove the archive empty before a date or relevance query starts.
  /// Other deletion selections may still exclude candidates inside this global boundary.
  func hasPotentiallyVisibleRecords() throws -> Bool {
    try sql.integer(
      "SELECT EXISTS(SELECT 1 FROM records WHERE sequence>\(VaultCleanupSelection.visibleSequenceBoundary))"
    ) != 0
  }

  /// A long transcript is removed over multiple slices before its source row is retired.
  @discardableResult public func performCleanupSlice() throws -> Set<UUID> {
    let removed = try sql.transaction { try cleanupRecords() }
    try recoverAttachments()
    return removed
  }

  func cleanupRecords() throws -> Set<UUID> {
    var removed: Set<UUID> = []
    var remainingBlocks = Self.cleanupBlockLimit
    for id in try cleanupCandidates() {
      try Task.checkCancellation()
      let values: [VaultSQLConnection.Value] = [.text(id.uuidString)]
      let count = try sql.integer(
        "SELECT count(*) FROM (SELECT id FROM content_blocks WHERE record_id=? LIMIT ?)",
        values + [.integer(Int64(remainingBlocks))])
      try sql.execute(
        "DELETE FROM content_blocks WHERE id IN (SELECT id FROM content_blocks WHERE record_id=? LIMIT ?)",
        values + [.integer(Int64(remainingBlocks))])
      remainingBlocks -= count
      if try sql.integer("SELECT EXISTS(SELECT 1 FROM content_blocks WHERE record_id=?)", values)
        == 0
      {
        try stageRetiredAttachments(id: id)
        try sql.execute("DELETE FROM records WHERE id=?", values)
        removed.insert(id)
      }
      if remainingBlocks == 0 { break }
    }
    try sql.execute(
      "UPDATE cleanup_policy SET removed=removed+? WHERE id=1",
      [.integer(Int64(removed.count))])
    try finishCleanupJobs()
    return removed
  }

  private func cleanupCandidates() throws -> [UUID] {
    var result = try identifiers(
      "SELECT record_id FROM pending_deletions ORDER BY record_id LIMIT ?",
      [.integer(Int64(Self.cleanupRecordLimit))])
    for kind in VaultCleanupSelection.allCases where result.count < Self.cleanupRecordLimit {
      let remaining = Self.cleanupRecordLimit - result.count
      let candidates = try identifiers(
        "SELECT r.id FROM records r JOIN vault_cleanup j ON j.kind=? WHERE \(kind.predicate) ORDER BY r.sequence LIMIT ?",
        [.text(kind.rawValue), .integer(Int64(remaining))])
      let seen = Set(result)
      result += candidates.filter { !seen.contains($0) }
    }
    return result
  }

  private func finishCleanupJobs() throws {
    for kind in VaultCleanupSelection.allCases {
      try sql.execute(
        "DELETE FROM vault_cleanup WHERE kind=? AND NOT EXISTS(SELECT 1 FROM records r JOIN vault_cleanup j ON j.kind=? WHERE \(kind.predicate))",
        [.text(kind.rawValue), .text(kind.rawValue)])
    }
    try enqueueRetentionIfNeeded()
  }

}
