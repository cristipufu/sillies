import Foundation
import SilliesCore

extension VaultLibrary {
  package nonisolated func recordingBookmarks(id: UUID) async throws -> [VaultRecordingBookmark] {
    try await documentReader.bookmarks(id: id)
  }
  package func saveRecordingBookmark(_ bookmark: VaultRecordingBookmark) throws {
    try storage().saveRecordingBookmark(bookmark)
  }
  package func removeRecordingBookmark(_ bookmark: VaultRecordingBookmark) throws {
    try storage().removeRecordingBookmark(bookmark)
  }
  package nonisolated func transcriptLocation(id: UUID, seconds: Double) async throws
    -> VaultBlockLocation?
  {
    try await documentReader.transcriptLocation(id: id, seconds: seconds)
  }
}
