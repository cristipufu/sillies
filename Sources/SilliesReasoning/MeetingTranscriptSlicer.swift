import Foundation
import SilliesTextModels

/// Source admission reserves enough room for both topic discovery and commitment extraction.
struct MeetingTranscriptSlicer {
  static let maximumChunkCharacters = 12_000
  let inference: NotesInference
  func slice(_ remainder: Substring, offset: Int) async throws -> MeetingTranscriptSlice {
    var count = remainder.prefix(Self.maximumChunkCharacters).count
    while count > 0 {
      try Task.checkCancellation()
      guard let text = MeetingTranscriptSlice.boundedPrefix(in: remainder, maximumCharacters: count)
      else { throw TextModelError.contextLimit }
      let slice = MeetingTranscriptSlice(text: text, offset: offset)
      if text.allSatisfy(\.isWhitespace) { return slice }
      if try await inference.admits(MeetingNotesPrompt.topics(slice), format: .meetingTopics),
        try await inference.admits(
          LocalActionEvidence.extractionRequest(slice.text), format: .actions)
      {
        return slice
      }
      count = text.count / 2
    }
    throw TextModelError.contextLimit
  }
}
