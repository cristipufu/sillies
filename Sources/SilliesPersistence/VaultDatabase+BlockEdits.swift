import Foundation
import SilliesCore

extension VaultDatabase {
  /// Editing the visible range never loads or replaces text outside it.
  func replaceBlocks(_ location: VaultBlockLocation, range: Range<Int>, text: String) throws -> UUID
  {
    if try sectionState(location) == nil {
      _ = try replaceContent(location, text: "", ownership: .authored)
    }
    let identity: [VaultSQLConnection.Value] = [
      .text(location.recordID.uuidString), .text(location.section.rawValue),
    ]
    let total = try sql.integer(
      "SELECT block_count FROM content_sections WHERE record_id=? AND section=?", identity)
    guard range.lowerBound >= 0, range.upperBound <= total,
      range.count <= VaultTextBlocks.maximumEditableBlocks,
      text.unicodeScalars.count <= VaultTextBlocks.maximumEditableScalars
    else { throw VaultEditingError.invalidValue }
    // Keep the known audio cue on the corrected range; never invent timing for new words.
    var anchor: (Double, String?)?
    try sql.rows(
      "SELECT start_seconds,coalesce(speaker,'') FROM content_blocks WHERE record_id=? AND section=? AND ordinal=? AND start_seconds IS NOT NULL",
      identity + [.integer(Int64(range.lowerBound))]
    ) { row in
      guard let time = Double(try VaultSQLConnection.text(row)), time.isFinite, time >= 0 else {
        return
      }
      let speaker = try VaultSQLConnection.text(row, column: 1)
      anchor = (time, speaker.isEmpty ? nil : speaker)
    }
    try sql.execute(
      "DELETE FROM content_blocks WHERE record_id=? AND section=? AND ordinal>=? AND ordinal<?",
      identity + [.integer(Int64(range.lowerBound)), .integer(Int64(range.upperBound))])
    // Negative staging positions avoid UNIQUE collisions when the edited block count changes.
    try sql.execute(
      "UPDATE content_blocks SET ordinal=-ordinal-1 WHERE record_id=? AND section=? AND ordinal>=?",
      identity + [.integer(Int64(range.upperBound))])
    var inserted = 0
    try VaultTextBlocks.enumerate(text) { offset, block in
      let (ordinal, overflow) = range.lowerBound.addingReportingOverflow(offset)
      guard !overflow else { throw VaultEditingError.invalidValue }
      try sql.execute(
        "INSERT INTO content_blocks(record_id,section,ordinal,text) VALUES(?,?,?,?)",
        identity + [.integer(Int64(ordinal)), .text(block)])
      inserted += 1
    }
    if let anchor, inserted > 0 {
      try sql.execute(
        "UPDATE content_blocks SET start_seconds=?,speaker=? WHERE record_id=? AND section=? AND ordinal=?",
        [.real(anchor.0), anchor.1.map(VaultSQLConnection.Value.text) ?? .null] + identity + [
          .integer(Int64(range.lowerBound))
        ])
    }
    let change = inserted - range.count
    let (newCount, overflow) = total.addingReportingOverflow(change)
    guard !overflow, newCount >= 0 else { throw VaultEditingError.invalidValue }
    try sql.execute(
      "UPDATE content_blocks SET ordinal=-ordinal-1+? WHERE record_id=? AND section=? AND ordinal<0",
      [.integer(Int64(change))] + identity)
    for ordinal in Set([range.lowerBound - 1, range.lowerBound + inserted - 1]) {
      try refreshSearchBoundary(
        .init(recordID: location.recordID, section: location.section, ordinal: ordinal))
    }
    let revision = UUID()
    try sql.execute(
      "UPDATE content_sections SET revision=?,digest=?,user_edited=1,block_count=? WHERE record_id=? AND section=?",
      [.text(revision.uuidString), .data(Data()), .integer(Int64(newCount))] + identity)
    return revision
  }
}
