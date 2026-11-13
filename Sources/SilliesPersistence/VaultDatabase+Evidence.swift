import Foundation
import SilliesCore

extension VaultDatabase {
  /// Reads only the blocks intersecting one admitted excerpt, with no source-body decoding.
  public func evidence(
    recordID: UUID, section: VaultDocumentSection, bytes: Range<Int>, expected: String
  ) throws -> [VaultEvidencePassage] {
    guard bytes.lowerBound >= 0, !bytes.isEmpty,
      expected.count <= VaultEvidencePassage.maximumCharacters,
      bytes.count == expected.utf8.count
    else { throw VaultEditingError.invalidValue }
    return try sql.readSnapshot {
      try sql.cancellableRead {
        try readEvidence(recordID: recordID, section: section, bytes: bytes, expected: expected)
      }
    }
  }

  private func readEvidence(
    recordID: UUID, section: VaultDocumentSection, bytes: Range<Int>, expected: String
  ) throws -> [VaultEvidencePassage] {
    guard try isRecordAvailable(recordID) else { return [] }
    var offsets: [(ordinal: Int, start: Int)] = []
    try sql.rows(
      """
      WITH positions AS (
        SELECT ordinal,length(CAST(text AS BLOB)) AS size,
          coalesce(sum(length(CAST(text AS BLOB))) OVER (ORDER BY ordinal ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) AS start
        FROM content_blocks WHERE record_id=? AND section=?
      )
      SELECT ordinal,start FROM positions WHERE start<? AND start+size>? ORDER BY ordinal LIMIT ?
      """,
      [
        .text(recordID.uuidString), .text(section.rawValue), .integer(Int64(bytes.upperBound)),
        .integer(Int64(bytes.lowerBound)),
        .integer(Int64(VaultEvidencePassage.maximumPerSource + 1)),
      ]
    ) { row in
      guard let ordinal = Int(try VaultSQLConnection.text(row)), ordinal >= 0,
        let start = Int(try VaultSQLConnection.text(row, column: 1)), start >= 0
      else { throw CocoaError(.fileReadCorruptFile) }
      offsets.append((ordinal, start))
    }
    guard offsets.count <= VaultEvidencePassage.maximumPerSource else { return [] }
    var passages: [VaultEvidencePassage] = []
    for offset in offsets {
      try Task.checkCancellation()
      let location = VaultBlockLocation(
        recordID: recordID, section: section, ordinal: offset.ordinal)
      guard let block = try contentBlocks(location, limit: 1).first else { return [] }
      let localStart = max(0, bytes.lowerBound - offset.start)
      let localEnd = min(block.text.utf8.count, bytes.upperBound - offset.start)
      guard localStart < localEnd else { return [] }
      let first = block.text.utf8.index(block.text.utf8.startIndex, offsetBy: localStart)
      let last = block.text.utf8.index(block.text.utf8.startIndex, offsetBy: localEnd)
      guard let start = first.samePosition(in: block.text.unicodeScalars),
        let end = last.samePosition(in: block.text.unicodeScalars)
      else { return [] }
      let scalarOffset = block.text.unicodeScalars.distance(
        from: block.text.startIndex, to: start)
      guard
        let passage = VaultEvidencePassage(
          block: block, scalarOffset: scalarOffset,
          text: String(block.text.unicodeScalars[start..<end]))
      else { return [] }
      passages.append(passage)
    }
    return passages.map(\.text).joined() == expected ? passages : []
  }

  public func evidenceLocation(_ passage: VaultEvidencePassage) throws -> VaultBlockLocation? {
    try sql.readSnapshot {
      guard let location = try sourceLocation(passage.reference),
        let block = try contentBlocks(location, limit: 1).first,
        passage.range(in: block) != nil
      else { return nil }
      return location
    }
  }
}
