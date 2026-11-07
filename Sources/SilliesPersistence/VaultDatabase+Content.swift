import CryptoKit
import Foundation
import SilliesCore

extension VaultDatabase {
  private struct SourceSection {
    let kind: VaultDocumentSection
    let text: String
  }

  func updateSourceSections(_ record: SessionRecord) throws {
    for section in sourceSections(record) {
      let address = VaultBlockLocation(recordID: record.id, section: section.kind)
      guard try sectionState(address)?.isEdited != true else { continue }
      _ = try replaceContent(address, text: section.text, ownership: .source)
    }
    let original = VaultBlockLocation(recordID: record.id, section: .originalTranscript)
    _ = try replaceContent(
      original, text: record.originalSpeakerTranscript ?? record.transcript, ownership: .source)
    try updateTranscriptAnchors(record)
    try updateFileReferences(record)
    // Version-one/two whole-document search is only a migration fallback. Keeping a second,
    // unbounded FTS copy would undo the bounded section storage and deletion guarantees.
    try retireLegacySearchDocument(id: record.id)
    try sql.execute("DELETE FROM content_backfill WHERE record_id=?", [.text(record.id.uuidString)])
  }

  private func retireLegacySearchDocument(id: UUID) throws {
    let identity = try sql.integer(
      "SELECT document_rowid FROM document_identities WHERE record_id=?", [.text(id.uuidString)])
    guard identity >= 0 else { throw CocoaError(.fileReadCorruptFile) }
    guard identity > 0 else { return }
    try sql.execute("DELETE FROM documents WHERE rowid=?", [.integer(Int64(identity))])
    try sql.execute("DELETE FROM document_identities WHERE record_id=?", [.text(id.uuidString)])
  }

  private func refreshSourceHeader(_ record: SessionRecord) throws {
    try sql.execute(
      "UPDATE records SET header=? WHERE id=?",
      [.data(try encoder.encode(SessionRecordHeader(record))), .text(record.id.uuidString)])
  }

  private func sourceSections(_ record: SessionRecord) -> [SourceSection] {
    [
      .init(kind: .title, text: record.displayTitle),
      .init(kind: .transcript, text: record.transcript),
      .init(kind: .summary, text: record.summary),
      .init(kind: .screenshotText, text: record.extractedText),
      .init(kind: .explanation, text: record.explanation),
      .init(kind: .actions, text: record.actionItems.joined(separator: "\n")),
      .init(kind: .stash, text: record.stashedItems.joined(separator: "\n")),
      .init(
        kind: .suggestions,
        text: record.suggestions.map { $0.question + "\n" + $0.evidence }.joined(separator: "\n\n")),
    ]
  }

  public func prepareNextContent() throws -> Bool {
    try Task.checkCancellation()
    var identity: UUID?
    try sql.rows("SELECT record_id FROM content_backfill ORDER BY sequence LIMIT 1") { row in
      guard let id = UUID(uuidString: try VaultSQLConnection.text(row)) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      identity = id
    }
    guard let identity else { return false }
    try sql.transaction {
      if let record = try record(id: identity) {
        try updateSourceSections(record)
        try refreshSourceHeader(record)
      }
      try sql.execute(
        "DELETE FROM content_backfill WHERE record_id=?", [.text(identity.uuidString)])
    }
    return true
  }

  public func prepareContent(id: UUID) throws {
    guard
      try sql.integer(
        "SELECT count(*) FROM content_backfill WHERE record_id=?", [.text(id.uuidString)]) > 0
    else { return }
    try sql.transaction {
      if let record = try record(id: id) {
        try updateSourceSections(record)
        try refreshSourceHeader(record)
      }
    }
  }

  enum ContentOwnership: Int { case source, authored }
  struct SectionState {
    let revision: UUID
    let digest: Data
    let isEdited: Bool
  }

  func sectionState(_ location: VaultBlockLocation) throws -> SectionState? {
    guard try isRecordAvailable(location.recordID) else { return nil }
    var state: SectionState?
    try sql.rows(
      "SELECT revision,digest,user_edited FROM content_sections WHERE record_id=? AND section=?",
      [.text(location.recordID.uuidString), .text(location.section.rawValue)]
    ) { row in
      guard let revision = UUID(uuidString: try VaultSQLConnection.text(row)) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      state = .init(
        revision: revision, digest: try VaultSQLConnection.data(row, column: 1),
        isEdited: try VaultSQLConnection.text(row, column: 2) == "1")
    }
    return state
  }

  @discardableResult func replaceContent(
    _ location: VaultBlockLocation, text: String, ownership: ContentOwnership
  ) throws -> UUID {
    let digest = Data(SHA256.hash(data: Data(text.utf8)))
    let previous = try sectionState(location)
    if let previous, previous.digest == digest {
      return previous.revision
    }
    let revision = UUID()
    let identity: [VaultSQLConnection.Value] = [
      .text(location.recordID.uuidString), .text(location.section.rawValue),
    ]
    if previous != nil {
      try sql.execute("DELETE FROM content_blocks WHERE record_id=? AND section=?", identity)
    }
    var count = 0
    try VaultTextBlocks.enumerate(text) { ordinal, block in
      try sql.execute(
        "INSERT INTO content_blocks(record_id,section,ordinal,text) VALUES(?,?,?,?)",
        identity + [.integer(Int64(ordinal)), .text(block)])
      count += 1
    }
    try sql.execute(
      """
      INSERT INTO content_sections(record_id,section,revision,digest,user_edited,block_count) VALUES(?,?,?,?,?,?)
      ON CONFLICT(record_id,section) DO UPDATE SET revision=excluded.revision,digest=excluded.digest,
        user_edited=excluded.user_edited,block_count=excluded.block_count
      """,
      identity + [
        .text(revision.uuidString), .data(digest), .integer(Int64(ownership.rawValue)),
        .integer(Int64(count)),
      ])
    if location.section != .originalTranscript { metrics.indexedSections += 1 }
    return revision
  }
}
