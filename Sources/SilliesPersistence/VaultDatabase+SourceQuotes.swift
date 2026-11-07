import Foundation
import SilliesCore

extension VaultDatabase {
  /// Resolve stable block identities before ordinals; edits can move later blocks.
  public func sourceLocation(_ reference: VaultSourceReference) throws -> VaultBlockLocation? {
    guard let header = try documentHeader(id: reference.location.recordID),
      header.metadata.trashedAt == nil
    else { return nil }
    var location: VaultBlockLocation?
    try sql.rows(
      "SELECT ordinal FROM content_blocks WHERE id=? AND record_id=? AND section=?",
      [
        .integer(reference.blockID), .text(reference.location.recordID.uuidString),
        .text(reference.location.section.rawValue),
      ]
    ) { row in
      guard let ordinal = Int(try VaultSQLConnection.text(row)), ordinal >= 0 else {
        throw CocoaError(.fileReadCorruptFile)
      }
      location = .init(
        recordID: reference.location.recordID, section: reference.location.section, ordinal: ordinal
      )
    }
    return location
  }

  /// Append to current persisted notes atomically, without materializing the existing document.
  public func appendQuote(_ quote: VaultQuotedPassage, to id: UUID, at date: Date) throws
    -> VaultBlockLocation
  {
    try sql.transaction {
      guard let header = try documentHeader(id: id), header.metadata.trashedAt == nil else {
        throw VaultEditingError.missingRecord
      }
      let location = VaultBlockLocation(recordID: id, section: .notes)
      guard try draft(location) == nil else { throw VaultEditingError.revisionConflict }
      let count = try sql.integer(
        "SELECT coalesce(sum(block_count),0) FROM content_sections WHERE record_id=? AND section='notes'",
        [.text(id.uuidString)])
      guard count >= 0, count < Int.max - VaultTextBlocks.maximumEditableBlocks else {
        throw VaultEditingError.invalidValue
      }
      let last = max(0, count - 1)
      let page = try sectionPage(.init(recordID: id, section: .notes, ordinal: last))
      let prefix = page.blocks.first?.text ?? ""
      let text = prefix + (count == 0 ? "" : "\n\n") + quote.markdown
      _ = try applyTextEdit(
        .init(
          location: location, expectedRevision: sectionRevision(location),
          text: text, region: .blocks(last..<count)), at: date)
      return .init(recordID: id, section: .notes, ordinal: last)
    }
  }
}
