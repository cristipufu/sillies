import Foundation
import SilliesCore

extension VaultDatabase {
  public func authoredNotes(recordID: UUID) throws -> String {
    try sectionText(.init(recordID: recordID, section: .notes))
  }
  public func sectionRevision(_ location: VaultBlockLocation) throws -> UUID? {
    try sectionState(location)?.revision
  }

  /// A visible page is bounded independently of the number of sessions or the source's length.
  public func sectionPage(_ location: VaultBlockLocation) throws -> VaultSectionPage {
    guard location.ordinal >= 0, location.ordinal <= Int.max - VaultSectionPage.maximumBlocks else {
      throw VaultEditingError.invalidValue
    }
    return try sql.cancellableRead {
      guard try isRecordAvailable(location.recordID) else {
        return .init(blocks: [], nextOrdinal: nil, previousOrdinal: nil)
      }
      var blocks = try contentBlocks(location, limit: VaultSectionPage.maximumBlocks + 1)
      let next =
        blocks.count > VaultSectionPage.maximumBlocks ? blocks.removeLast().location.ordinal : nil
      return .init(
        blocks: blocks, nextOrdinal: next,
        previousOrdinal: location.ordinal > 0
          ? max(0, location.ordinal - VaultSectionPage.maximumBlocks) : nil)
    }
  }

  func contentBlocks(_ location: VaultBlockLocation, limit: Int) throws -> [VaultContentBlock] {
    guard (0...VaultTextBlocks.maximumEditableBlocks).contains(limit) else {
      throw VaultEditingError.invalidValue
    }
    var blocks: [VaultContentBlock] = []
    try sql.rows(
      """
      SELECT b.id,b.ordinal,b.text,s.revision,coalesce(b.start_seconds,-1),coalesce(b.speaker,'')
      FROM content_blocks b JOIN content_sections s ON s.record_id=b.record_id AND s.section=b.section
      WHERE b.record_id=? AND b.section=? AND b.ordinal>=? ORDER BY b.ordinal LIMIT ?
      """,
      [
        .text(location.recordID.uuidString), .text(location.section.rawValue),
        .integer(Int64(location.ordinal)), .integer(Int64(limit)),
      ]
    ) { row in
      guard let id = Int64(try VaultSQLConnection.text(row)),
        let ordinal = Int(try VaultSQLConnection.text(row, column: 1)),
        let revision = UUID(uuidString: try VaultSQLConnection.text(row, column: 3)),
        let time = Double(try VaultSQLConnection.text(row, column: 4))
      else { throw CocoaError(.fileReadCorruptFile) }
      let speaker = try VaultSQLConnection.text(row, column: 5)
      blocks.append(
        .init(
          id: id,
          location: .init(
            recordID: location.recordID, section: location.section, ordinal: ordinal),
          revision: revision,
          text: try VaultSQLConnection.text(
            row, column: 2, maximumBytes: VaultTextBlocks.maximumScalars * 4),
          startSeconds: time >= 0 && time.isFinite ? time : nil,
          speaker: speaker.isEmpty ? nil : speaker))
    }
    return blocks
  }

  public func sectionKinds(recordID: UUID) throws -> [VaultDocumentSection] {
    guard try isRecordAvailable(recordID) else { return [] }
    var sections: [VaultDocumentSection] = []
    try sql.rows(
      "SELECT section FROM content_sections WHERE record_id=? AND block_count>0 ORDER BY section",
      [.text(recordID.uuidString)]
    ) { row in
      guard let kind = VaultDocumentSection(rawValue: try VaultSQLConnection.text(row)) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      sections.append(kind)
    }
    return sections
  }

  /// Full materialization is reserved for explicit exports and existing bounded reasoning callers.
  func sectionText(_ location: VaultBlockLocation) throws -> String {
    guard try isRecordAvailable(location.recordID) else { return "" }
    var text = ""
    try sql.rows(
      "SELECT text FROM content_blocks WHERE record_id=? AND section=? ORDER BY ordinal",
      [.text(location.recordID.uuidString), .text(location.section.rawValue)]
    ) { row in text += try VaultSQLConnection.text(row) }
    return text
  }
}
