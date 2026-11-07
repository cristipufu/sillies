import Foundation
import SilliesCore

extension VaultDatabase {
  func prepareMetadataDraftSchema() throws {
    try sql.execute(
      """
      CREATE TABLE IF NOT EXISTS vault_metadata_drafts(
        record_id TEXT PRIMARY KEY REFERENCES records(id) ON DELETE CASCADE, body BLOB NOT NULL)
      """)
  }

  public func metadataDraft(id: UUID) throws -> VaultMetadataDraft? {
    guard try isRecordAvailable(id) else { return nil }
    var draft: VaultMetadataDraft?
    try sql.rows("SELECT body FROM vault_metadata_drafts WHERE record_id=?", [.text(id.uuidString)])
    {
      let decoded = try decoder.decode(
        VaultMetadataDraft.self, from: VaultSQLConnection.data($0, maximumBytes: 32_768))
      guard decoded.recordID == id, decoded.isValid else { throw CocoaError(.fileReadCorruptFile) }
      draft = decoded
    }
    return draft
  }

  public func saveMetadataDraft(_ draft: VaultMetadataDraft) throws {
    guard draft.isValid else { throw VaultEditingError.invalidValue }
    guard try documentHeader(id: draft.recordID) != nil else {
      throw VaultEditingError.missingRecord
    }
    try sql.execute(
      "INSERT INTO vault_metadata_drafts VALUES(?,?) ON CONFLICT(record_id) DO UPDATE SET body=excluded.body",
      [.text(draft.recordID.uuidString), .data(try encoder.encode(draft))])
  }

  public func commitMetadataDraft(_ draft: VaultMetadataDraft, at date: Date) throws
    -> VaultDocumentHeader
  {
    guard draft.isValid else { throw VaultEditingError.invalidValue }
    return try sql.transaction {
      guard let current = try documentHeader(id: draft.recordID), current.metadata.trashedAt == nil
      else { throw VaultEditingError.missingRecord }
      var metadata = current.metadata
      if let title = draft.title { try apply(.rename(title), to: &metadata, at: date) }
      if let tags = draft.tags { try apply(.tags(tags), to: &metadata, at: date) }
      try storeWorkspace(id: draft.recordID, metadata: metadata)
      guard let header = try documentHeader(id: draft.recordID) else {
        throw VaultEditingError.missingRecord
      }
      if try metadataDraft(id: draft.recordID)?.id == draft.id {
        try sql.execute(
          "DELETE FROM vault_metadata_drafts WHERE record_id=?", [.text(draft.recordID.uuidString)])
      }
      return header
    }
  }
}
