import Foundation
import SilliesCore

extension VaultDatabase {
  /// The cleanup journal protects filesystem work on either side of the SQLite transaction.
  @discardableResult public func commit(_ mutation: VaultMutation) throws -> Set<UUID> {
    var removed: Set<UUID> = []
    for attachment in mutation.attachments { try stageCleanup(attachment.filename) }
    for attachment in mutation.attachments {
      try files.write(attachment.data, named: attachment.filename)
    }
    let priorMetrics = metrics
    do {
      try sql.transaction {
        try enqueueDeletion(mutation.deletion)
        if case .records(let ids) = mutation.deletion { removed.formUnion(ids) }
        for write in mutation.records {
          let record = write.record
          if case .insert = write { try retireHiddenRecordForInsertion(record.id) }
          if case .update = write,
            try sql.integer(
              "SELECT count(*) FROM available_records WHERE id=?", [.text(record.id.uuidString)])
              == 0
          {
            // Retention may have removed a record while its field edit was loading.
            // Invalidate optimistic headers/details even when there is no row left to update.
            removed.insert(record.id)
            continue
          }
          try stageRetiredAttachments(id: record.id)
          try store(record)
        }
        try requestRetention(mutation.retention)
        removed.formUnion(try cleanupRecords())
      }
    } catch {
      metrics = priorMetrics
      throw error
    }
    try recoverAttachments()
    return removed
  }

  func stageRetiredAttachments(id: UUID) throws {
    let values: [VaultSQLConnection.Value] = [.text(id.uuidString)]
    try sql.execute(
      "INSERT OR IGNORE INTO attachment_cleanup SELECT image FROM records WHERE id=? AND image IS NOT NULL",
      values)
    try sql.execute(
      "INSERT OR IGNORE INTO attachment_cleanup SELECT audio FROM records WHERE id=? AND audio IS NOT NULL",
      values)
    try sql.execute(
      "INSERT OR IGNORE INTO attachment_cleanup SELECT preview_image FROM workspace WHERE preview_image IS NOT NULL AND record_id=?",
      values)
  }

  func stageCleanup(_ filename: String) throws {
    _ = try files.attachmentURL(for: filename)
    try sql.execute("INSERT OR IGNORE INTO attachment_cleanup VALUES(?)", [.text(filename)])
  }

  func recoverAttachments() throws {
    let batchSize: Int64 = 128
    _ = try recoverAttachmentBatch(limit: batchSize)
  }

  private func recoverAttachmentBatch(limit: Int64) throws -> Int {
    var filenames: [String] = []
    try sql.rows(
      "SELECT filename FROM attachment_cleanup ORDER BY filename LIMIT ?", [.integer(limit)]
    ) {
      filenames.append(try VaultSQLConnection.text($0))
    }
    for filename in filenames {
      let references = try sql.integer(
        "SELECT (SELECT count(*) FROM records WHERE image=? OR audio=?) + (SELECT count(*) FROM workspace WHERE preview_image=?)",
        [.text(filename), .text(filename), .text(filename)])
      if references == 0 { try files.removeAttachment(named: filename) }
      try sql.execute("DELETE FROM attachment_cleanup WHERE filename=?", [.text(filename)])
    }
    return filenames.count
  }
}
