import Foundation
import SilliesCore

extension VaultDatabase {
  private static let maximumBatchEdit = 256

  public func editDocuments(ids: Set<UUID>, edit: VaultDocumentEdit, at date: Date) throws {
    guard ids.count <= Self.maximumBatchEdit else { throw VaultEditingError.invalidValue }
    try sql.transaction {
      for id in ids {
        try Task.checkCancellation()
        guard let header = try documentHeader(id: id) else { continue }
        var metadata = header.metadata
        try apply(edit, to: &metadata, at: date)
        try storeWorkspace(id: id, metadata: metadata)
      }
    }
  }

  @discardableResult public func editDocument(
    id: UUID, edit: VaultDocumentEdit, at date: Date
  ) throws -> VaultDocumentHeader {
    try sql.transaction {
      guard let header = try documentHeader(id: id) else { throw VaultEditingError.missingRecord }
      var metadata = header.metadata
      try apply(edit, to: &metadata, at: date)
      try storeWorkspace(id: id, metadata: metadata)
      guard let updated = try documentHeader(id: id) else { throw VaultEditingError.missingRecord }
      return updated
    }
  }

  @discardableResult public func editText(_ edit: VaultTextEdit, at date: Date) throws -> UUID {
    try sql.transaction { try applyTextEdit(edit, at: date) }
  }

  func applyTextEdit(_ edit: VaultTextEdit, at date: Date) throws -> UUID {
    guard [.notes, .transcript, .screenshotText].contains(edit.location.section) else {
      throw VaultEditingError.invalidValue
    }
    guard let header = try documentHeader(id: edit.location.recordID),
      header.metadata.trashedAt == nil
    else {
      throw VaultEditingError.missingRecord
    }
    guard try sectionRevision(edit.location) == edit.expectedRevision else {
      throw VaultEditingError.revisionConflict
    }
    let revision: UUID
    switch edit.region {
    case .entireSection:
      revision = try replaceContent(edit.location, text: edit.text, ownership: .authored)
    case .blocks(let range):
      revision = try replaceBlocks(edit.location, range: range, text: edit.text)
    }
    var metadata = header.metadata
    metadata.modifiedAt = date
    try storeWorkspace(id: header.id, metadata: metadata)
    return revision
  }

  public func createDocument(
    record: SessionRecord, metadata: VaultDocumentMetadata, notes: String = ""
  ) throws -> VaultDocumentHeader {
    try sql.transaction {
      guard try documentHeader(id: record.id) == nil else { throw VaultEditingError.invalidValue }
      try store(record)
      try storeWorkspace(id: record.id, metadata: metadata)
      _ = try replaceContent(
        .init(recordID: record.id, section: .notes), text: notes, ownership: .authored)
      guard let header = try documentHeader(id: record.id) else {
        throw VaultEditingError.missingRecord
      }
      return header
    }
  }

  func apply(
    _ edit: VaultDocumentEdit, to metadata: inout VaultDocumentMetadata, at date: Date
  ) throws {
    switch edit {
    case .rename(let title):
      guard title.unicodeScalars.count <= VaultDocumentMetadata.maximumTitleScalars else {
        throw VaultEditingError.invalidValue
      }
      metadata.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    case .star: metadata.isStarred = true
    case .unstar: metadata.isStarred = false
    case .moveToTrash: metadata.trashedAt = date
    case .restore: metadata.trashedAt = nil
    case .tags(let tags):
      guard tags.count <= VaultDocumentMetadata.maximumTags,
        tags.allSatisfy({
          !$0.isEmpty && $0.unicodeScalars.count <= VaultDocumentMetadata.maximumTagScalars
        })
      else {
        throw VaultEditingError.invalidValue
      }
      metadata.tags = Array(Set(tags)).sorted()
    case .collections(let ids):
      guard ids.count <= VaultDocumentMetadata.maximumCollections else {
        throw VaultEditingError.invalidValue
      }
      metadata.collectionIDs = Array(Set(ids)).sorted { $0.uuidString < $1.uuidString }
    case .addToCollection(let id):
      let ids = Set(metadata.collectionIDs).union([id])
      guard ids.count <= VaultDocumentMetadata.maximumCollections else {
        throw VaultEditingError.invalidValue
      }
      metadata.collectionIDs = ids.sorted { $0.uuidString < $1.uuidString }
    case .removeFromCollection(let id):
      metadata.collectionIDs.removeAll { $0 == id }
    case .linkPreview(let link):
      guard metadata.link?.url == link.url else { throw VaultEditingError.revisionConflict }
      if metadata.title == metadata.link?.title { metadata.title = link.title }
      metadata.link = link
    }
    metadata.modifiedAt = date
  }

  func storeWorkspace(id: UUID, metadata: VaultDocumentMetadata) throws {
    guard metadata.isValid else { throw VaultEditingError.invalidValue }
    var stored = metadata
    stored.tags = []
    stored.collectionIDs = []
    try sql.execute(
      """
      INSERT INTO workspace(record_id,kind,title,modified,starred,trashed,metadata) VALUES(?,?,?,?,?,?,?)
      ON CONFLICT(record_id) DO UPDATE SET kind=excluded.kind,title=excluded.title,modified=excluded.modified,
        starred=excluded.starred,trashed=excluded.trashed,metadata=excluded.metadata
      """,
      [
        .text(id.uuidString), .text(metadata.kind.rawValue), .text(metadata.title),
        .real(metadata.modifiedAt.timeIntervalSince1970), .integer(metadata.isStarred ? 1 : 0),
        metadata.trashedAt.map { .real($0.timeIntervalSince1970) } ?? .null,
        .data(try encoder.encode(stored)),
      ])
    try storeOrganization(id: id, metadata: metadata)
    try sql.execute(
      "UPDATE workspace SET preview_state=?,preview_image=? WHERE record_id=?",
      [
        metadata.link.map { .text($0.previewState.rawValue) } ?? .null,
        metadata.link?.imageFilename.map(VaultSQLConnection.Value.text) ?? .null,
        .text(id.uuidString),
      ])
    if let source = try documentHeader(id: id)?.source {
      _ = try replaceContent(
        .init(recordID: id, section: .title),
        text: metadata.title.isEmpty ? source.displayTitle : metadata.title, ownership: .authored)
    }
    _ = try replaceContent(
      .init(recordID: id, section: .labels), text: metadata.tags.joined(separator: " "),
      ownership: .authored)
    if let link = metadata.link {
      _ = try replaceContent(
        .init(recordID: id, section: .linkText),
        text: [link.title, link.author, link.description, link.url.absoluteString].joined(
          separator: "\n"), ownership: .source)
    }
  }

  private func storeOrganization(id: UUID, metadata: VaultDocumentMetadata) throws {
    try sql.execute("DELETE FROM vault_tags WHERE record_id=?", [.text(id.uuidString)])
    for tag in metadata.tags {
      try sql.execute("INSERT INTO vault_tags VALUES(?,?)", [.text(tag), .text(id.uuidString)])
    }
    try sql.execute("DELETE FROM vault_collection_items WHERE record_id=?", [.text(id.uuidString)])
    for collection in metadata.collectionIDs {
      guard
        try sql.integer(
          "SELECT count(*) FROM vault_collections WHERE id=?", [.text(collection.uuidString)]) == 1
      else {
        throw VaultEditingError.invalidValue
      }
      try sql.execute(
        "INSERT INTO vault_collection_items VALUES(?,?)",
        [.text(collection.uuidString), .text(id.uuidString)])
    }
  }
}
