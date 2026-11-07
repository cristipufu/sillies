import Foundation
import SilliesCore

extension VaultDatabase {
  /// Locate structured segments in the saved source, never guess a time from an edited sentence.
  func updateTranscriptAnchors(_ record: SessionRecord) throws {
    let location = VaultBlockLocation(recordID: record.id, section: .transcript)
    guard try sectionState(location)?.isEdited == false, !record.transcriptSegments.isEmpty else {
      return
    }
    var cursor = record.transcript.startIndex
    var offset = 0
    var anchors: [(offset: Int, time: Double, speaker: String?)] = []
    for segment in record.transcriptSegments {
      guard segment.start.isFinite, segment.start >= 0, !segment.text.isEmpty,
        let range = record.transcript.range(
          of: segment.text, range: cursor..<record.transcript.endIndex)
      else { continue }
      offset += record.transcript[cursor..<range.lowerBound].unicodeScalars.count
      anchors.append((offset, segment.start, segment.speaker?.label))
      offset += record.transcript[range].unicodeScalars.count
      cursor = range.upperBound
    }
    var scalarOffset = 0
    var anchorIndex = 0
    try VaultTextBlocks.enumerate(record.transcript) { ordinal, text in
      while anchorIndex + 1 < anchors.count, anchors[anchorIndex + 1].offset <= scalarOffset {
        anchorIndex += 1
      }
      if anchors.indices.contains(anchorIndex) {
        let anchor = anchors[anchorIndex]
        try sql.execute(
          "UPDATE content_blocks SET start_seconds=?,speaker=? WHERE record_id=? AND section='transcript' AND ordinal=?",
          [
            .real(anchor.time), anchor.speaker.map(VaultSQLConnection.Value.text) ?? .null,
            .text(record.id.uuidString), .integer(Int64(ordinal)),
          ])
      }
      scalarOffset += text.unicodeScalars.count
    }
  }
}
