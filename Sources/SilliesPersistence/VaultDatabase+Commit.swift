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
        switch mutation.deletion {
        case .all:
          try stageRetiredAttachments()
          try sql.execute("DELETE FROM records")
          try sql.execute("DELETE FROM documents")
        case .records(let ids):
          for id in ids {
            try remove(id)
            removed.insert(id)
          }
        }
        for write in mutation.records {
          let record = write.record
          if case .update = write,
            try sql.integer(
              "SELECT count(*) FROM records WHERE id=?", [.text(record.id.uuidString)]) == 0
          {
            // Retention may have removed a record while its field edit was loading.
            // Invalidate optimistic headers/details even when there is no row left to update.
            removed.insert(record.id)
            continue
          }
          try stageRetiredAttachments(id: record.id)
          try store(record)
        }
        if let limit = mutation.retention.limit {
          let expired = try identifiers(
            "SELECT id FROM records WHERE kind != ? AND protected=0 ORDER BY created DESC, id DESC LIMIT -1 OFFSET ?",
            [.text(CompanionSkillKind.stash.rawValue), .integer(Int64(limit))])
          for id in expired {
            try remove(id)
            removed.insert(id)
          }
        }
      }
    } catch {
      metrics = priorMetrics
      throw error
    }
    try recoverAttachments()
    return removed
  }

  private func remove(_ id: UUID) throws {
    try stageRetiredAttachments(id: id)
    try sql.execute("DELETE FROM records WHERE id=?", [.text(id.uuidString)])
    try sql.execute("DELETE FROM documents WHERE id=?", [.text(id.uuidString)])
  }

  private func stageRetiredAttachments(id: UUID? = nil) throws {
    let filter = id == nil ? "" : "WHERE id=?"
    let values: [VaultSQLConnection.Value] = id.map { [.text($0.uuidString)] } ?? []
    try sql.execute(
      "INSERT OR IGNORE INTO attachment_cleanup SELECT image FROM records \(filter) \(id == nil ? "WHERE" : "AND") image IS NOT NULL",
      values)
    try sql.execute(
      "INSERT OR IGNORE INTO attachment_cleanup SELECT audio FROM records \(filter) \(id == nil ? "WHERE" : "AND") audio IS NOT NULL",
      values)
  }

  func stageCleanup(_ filename: String) throws {
    _ = try files.attachmentURL(for: filename)
    try sql.execute("INSERT OR IGNORE INTO attachment_cleanup VALUES(?)", [.text(filename)])
  }

  func recoverAttachments() throws {
    var filenames: [String] = []
    try sql.rows("SELECT filename FROM attachment_cleanup") {
      filenames.append(try VaultSQLConnection.text($0))
    }
    for filename in filenames {
      let references = try sql.integer(
        "SELECT count(*) FROM records WHERE image=? OR audio=?", [.text(filename), .text(filename)])
      if references == 0 { try files.removeAttachment(named: filename) }
      try sql.execute("DELETE FROM attachment_cleanup WHERE filename=?", [.text(filename)])
    }
  }
}
