import Foundation
import SilliesCore

extension VaultDatabase {
  public func saveDraft(_ draft: VaultDraft) throws {
    guard draft.isValid else {
      throw VaultEditingError.invalidValue
    }
    guard try documentHeader(id: draft.location.recordID) != nil else {
      throw VaultEditingError.missingRecord
    }
    try sql.execute(
      "INSERT INTO vault_drafts VALUES(?,?,?) ON CONFLICT(record_id,section) DO UPDATE SET body=excluded.body",
      [
        .text(draft.location.recordID.uuidString), .text(draft.location.section.rawValue),
        .data(try encoder.encode(draft)),
      ])
  }

  public func draft(_ location: VaultBlockLocation) throws -> VaultDraft? {
    guard try isRecordAvailable(location.recordID) else { return nil }
    var result: VaultDraft?
    try sql.rows(
      "SELECT body FROM vault_drafts WHERE record_id=? AND section=?",
      [.text(location.recordID.uuidString), .text(location.section.rawValue)]
    ) { row in
      let draft = try decoder.decode(
        VaultDraft.self,
        from: VaultSQLConnection.data(
          row, maximumBytes: VaultTextBlocks.maximumEditableScalars * 4 + 2_048))
      guard draft.isValid else { throw CocoaError(.fileReadCorruptFile) }
      result = draft
    }
    return result
  }

  public func commitDraft(_ draft: VaultDraft, at date: Date) throws -> VaultDraftCommit {
    try sql.transaction {
      let revision = try applyTextEdit(draft.edit, at: date)
      var count = 0
      VaultTextBlocks.enumerate(draft.text) { _, _ in count += 1 }
      let blocks = try contentBlocks(draft.location, limit: count)
      if try self.draft(draft.location)?.id == draft.id { try discardDraft(draft.location) }
      return .init(revision: revision, blocks: blocks)
    }
  }

  public func discardDraft(_ location: VaultBlockLocation) throws {
    try sql.execute(
      "DELETE FROM vault_drafts WHERE record_id=? AND section=?",
      [.text(location.recordID.uuidString), .text(location.section.rawValue)])
  }
}
