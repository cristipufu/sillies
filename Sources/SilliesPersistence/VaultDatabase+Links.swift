import Foundation
import SilliesCore

extension VaultDatabase {
  public func pendingLink() throws -> VaultDocumentHeader? {
    var id: UUID?
    try sql.rows(
      "SELECT record_id FROM workspace WHERE preview_state='pending' AND trashed IS NULL AND record_id IN (SELECT id FROM available_records) ORDER BY modified,record_id LIMIT 1"
    ) { row in
      guard let value = UUID(uuidString: try VaultSQLConnection.text(row)) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      id = value
    }
    return try id.flatMap { try documentHeader(id: $0) }
  }

  @discardableResult public func saveLinkPreview(
    _ preview: VaultLinkPreview, id: UUID, at date: Date
  ) throws -> VaultDocumentHeader? {
    guard let header = try documentHeader(id: id), header.metadata.link?.url == preview.link.url,
      header.metadata.trashedAt == nil
    else { return nil }
    var link = preview.link
    if let image = preview.image {
      let filename = "link-\(id.uuidString)-\(UUID().uuidString).png"
      try stageCleanup(filename)
      try files.write(image, named: filename)
      link.imageFilename = filename
    }
    if let previous = header.metadata.link?.imageFilename { try stageCleanup(previous) }
    let updated = try editDocument(id: id, edit: .linkPreview(link), at: date)
    try recoverAttachments()
    return updated
  }
}
