import Foundation
import SilliesCore

extension VaultDatabase {
  func prepareRecordingNavigation() throws {
    try sql.execute(
      "CREATE TABLE recording_bookmarks(id TEXT PRIMARY KEY, record_id TEXT NOT NULL, seconds REAL NOT NULL, label TEXT NOT NULL)"
    )
    try sql.execute(
      "CREATE INDEX recording_bookmarks_order ON recording_bookmarks(record_id,seconds,id)")
    try sql.execute(
      "CREATE INDEX transcript_time ON content_blocks(record_id,section,start_seconds,ordinal)")
    try sql.execute(
      "CREATE TRIGGER record_bookmark_delete AFTER DELETE ON records BEGIN DELETE FROM recording_bookmarks WHERE record_id=old.id; END"
    )
  }
  public func recordingBookmarks(id: UUID) throws -> [VaultRecordingBookmark] {
    guard try isRecordAvailable(id) else { return [] }
    var result: [VaultRecordingBookmark] = []
    try sql.rows(
      "SELECT id,seconds,label FROM recording_bookmarks WHERE record_id=? ORDER BY seconds,id LIMIT ?",
      [.text(id.uuidString), .integer(Int64(VaultRecordingBookmark.maximumPerRecording))]
    ) { row in
      guard let bookmarkID = UUID(uuidString: try VaultSQLConnection.text(row)),
        let seconds = Double(try VaultSQLConnection.text(row, column: 1))
      else { throw CocoaError(.fileReadCorruptFile) }
      let bookmark = VaultRecordingBookmark(
        id: bookmarkID, recordID: id, seconds: seconds,
        label: try VaultSQLConnection.text(
          row, column: 2, maximumBytes: VaultRecordingBookmark.maximumLabelScalars * 4))
      guard bookmark.isValid else { throw CocoaError(.fileReadCorruptFile) }
      result.append(bookmark)
    }
    return result
  }
  public func saveRecordingBookmark(_ bookmark: VaultRecordingBookmark) throws {
    guard bookmark.isValid else { throw VaultEditingError.invalidValue }
    try sql.transaction {
      guard let header = try documentHeader(id: bookmark.recordID),
        header.metadata.trashedAt == nil,
        header.source.audioFilename != nil
      else { throw VaultEditingError.missingRecord }
      let count = try sql.integer(
        "SELECT count(*) FROM recording_bookmarks WHERE record_id=? AND id!=?",
        [.text(bookmark.recordID.uuidString), .text(bookmark.id.uuidString)])
      guard count < VaultRecordingBookmark.maximumPerRecording else {
        throw VaultEditingError.bookmarkLimit
      }
      try sql.execute(
        "INSERT INTO recording_bookmarks VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET label=excluded.label WHERE record_id=excluded.record_id",
        [
          .text(bookmark.id.uuidString), .text(bookmark.recordID.uuidString),
          .real(bookmark.seconds), .text(bookmark.label),
        ])
    }
  }
  public func removeRecordingBookmark(_ bookmark: VaultRecordingBookmark) throws {
    try sql.execute(
      "DELETE FROM recording_bookmarks WHERE id=? AND record_id=?",
      [.text(bookmark.id.uuidString), .text(bookmark.recordID.uuidString)])
  }
  public func transcriptLocation(id: UUID, seconds: Double) throws -> VaultBlockLocation? {
    guard seconds.isFinite, seconds >= 0 else { throw VaultEditingError.invalidValue }
    guard try isRecordAvailable(id) else { return nil }
    var location: VaultBlockLocation?
    try sql.rows(
      """
      SELECT ordinal FROM content_blocks WHERE record_id=? AND section='transcript' AND start_seconds=(
        SELECT max(start_seconds) FROM content_blocks WHERE record_id=? AND section='transcript' AND start_seconds<=?)
      ORDER BY ordinal LIMIT 1
      """, [.text(id.uuidString), .text(id.uuidString), .real(seconds)]
    ) { row in
      guard let ordinal = Int(try VaultSQLConnection.text(row)), ordinal >= 0 else {
        throw CocoaError(.fileReadCorruptFile)
      }
      location = .init(recordID: id, section: .transcript, ordinal: ordinal)
    }
    return location
  }
}
