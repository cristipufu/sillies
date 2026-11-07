import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func vaultBookmarksPersistAndTranscriptCorrectionsRetainKnownAudioCues() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  var record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")),
    content: .init(text: .init(transcript: "Original words")))
  record.audioFilename = "recording.m4a"
  record.transcriptSegments = [
    .init(sequence: 0, source: "microphone", start: 4, end: 7, text: "Original words")
  ]
  try database.commit(.init(records: [.insert(record)]))
  let bookmark = VaultRecordingBookmark(recordID: record.id, seconds: 5, label: "Decision")
  try database.saveRecordingBookmark(bookmark)
  #expect(try database.recordingBookmarks(id: record.id) == [bookmark])
  let location = VaultBlockLocation(recordID: record.id, section: .transcript)
  #expect(try database.transcriptLocation(id: record.id, seconds: 5) == location)
  _ = try database.editText(
    .init(
      location: location, expectedRevision: database.sectionRevision(location),
      text: "Corrected words", region: .blocks(0..<1)), at: Date())
  #expect(try database.sectionPage(location).blocks.first?.startSeconds == 4)
  #expect(try database.transcriptLocation(id: record.id, seconds: 5) == location)
  let reopened = try VaultDatabase(reading: directory)
  #expect(try reopened.recordingBookmarks(id: record.id) == [bookmark])
  try database.editDocument(id: record.id, edit: .moveToTrash, at: Date())
  #expect(throws: VaultEditingError.self) { try database.saveRecordingBookmark(bookmark) }
  try database.commit(.init(deletion: .records([record.id])))
  #expect(try reopened.recordingBookmarks(id: record.id).isEmpty)
  #expect(database.metrics.loadedBodies == 0)
}

@Test func vaultBookmarksRejectInvalidTimesAndDoNotGrowWithoutBound() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let database = try VaultDatabase(directory: directory)
  var record = SessionRecord(
    kind: .record,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Fixture")))
  record.audioFilename = "recording.m4a"
  try database.commit(.init(records: [.insert(record)]))
  for seconds in [Double.nan, .infinity, -1] {
    #expect(throws: VaultEditingError.self) {
      try database.saveRecordingBookmark(
        .init(recordID: record.id, seconds: seconds, label: "Invalid"))
    }
  }
  for index in 0..<VaultRecordingBookmark.maximumPerRecording {
    try database.saveRecordingBookmark(
      .init(recordID: record.id, seconds: Double(index), label: "Moment"))
  }
  #expect(throws: VaultEditingError.self) {
    try database.saveRecordingBookmark(
      .init(recordID: record.id, seconds: 999, label: "Over limit"))
  }
  let first = try #require(database.recordingBookmarks(id: record.id).first)
  try database.removeRecordingBookmark(first)
  try database.saveRecordingBookmark(.init(recordID: record.id, seconds: 999, label: "Room again"))
  #expect(
    try database.recordingBookmarks(id: record.id).count
      == VaultRecordingBookmark.maximumPerRecording)
}
