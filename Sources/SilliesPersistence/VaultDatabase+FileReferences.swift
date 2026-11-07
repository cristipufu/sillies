import Foundation
import SilliesCore

extension VaultDatabase {
  func prepareFileReferences() throws {
    try sql.execute(
      "CREATE TABLE file_references(id TEXT PRIMARY KEY, record_id TEXT NOT NULL, original_path TEXT NOT NULL, path TEXT NOT NULL, UNIQUE(record_id,original_path))"
    )
    try sql.execute(
      "CREATE TRIGGER record_file_reference_delete AFTER DELETE ON records BEGIN DELETE FROM file_references WHERE record_id=old.id; END"
    )
  }
  func updateFileReferences(_ record: SessionRecord) throws {
    guard record.kind == .stash, try documentHeader(id: record.id)?.metadata.kind == .capture else {
      return
    }
    let paths = Set(
      record.stashedItems.filter(VaultFileReference.isValidPath).prefix(
        VaultFileReference.maximumPerItem))
    for reference in try fileReferences(id: record.id) where !paths.contains(reference.originalPath)
    {
      try sql.execute("DELETE FROM file_references WHERE id=?", [.text(reference.id.uuidString)])
    }
    for path in paths {
      try sql.execute(
        "INSERT OR IGNORE INTO file_references VALUES(?,?,?,?)",
        [.text(UUID().uuidString), .text(record.id.uuidString), .text(path), .text(path)])
    }
    try indexFileReferences(id: record.id)
  }
  public func fileReferences(id: UUID) throws -> [VaultFileReference] {
    guard try isRecordAvailable(id) else { return [] }
    var references: [VaultFileReference] = []
    try sql.rows(
      "SELECT id,original_path,path FROM file_references WHERE record_id=? ORDER BY id LIMIT ?",
      [.text(id.uuidString), .integer(Int64(VaultFileReference.maximumPerItem))]
    ) { row in
      guard let referenceID = UUID(uuidString: try VaultSQLConnection.text(row)) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      references.append(
        try .init(
          id: referenceID, recordID: id,
          originalPath: VaultSQLConnection.text(
            row, column: 1, maximumBytes: VaultFileReference.maximumPathScalars * 4),
          path: VaultSQLConnection.text(
            row, column: 2, maximumBytes: VaultFileReference.maximumPathScalars * 4)))
    }
    return references
  }
  public func relink(_ reference: VaultFileReference, to url: URL) throws {
    guard url.isFileURL, VaultFileReference.isValidPath(url.path) else {
      throw VaultEditingError.invalidValue
    }
    try sql.transaction {
      guard let header = try documentHeader(id: reference.recordID),
        header.metadata.trashedAt == nil
      else { throw VaultEditingError.missingRecord }
      guard try fileReferences(id: reference.recordID).contains(reference) else {
        throw VaultEditingError.revisionConflict
      }
      try sql.execute(
        "UPDATE file_references SET path=? WHERE id=? AND record_id=?",
        [.text(url.path), .text(reference.id.uuidString), .text(reference.recordID.uuidString)])
      try indexFileReferences(id: reference.recordID)
    }
  }
  private func indexFileReferences(id: UUID) throws {
    _ = try replaceContent(
      .init(recordID: id, section: .files),
      text: fileReferences(id: id).map(\.path).joined(separator: "\n"), ownership: .source)
  }
}
