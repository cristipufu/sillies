import Foundation
import SilliesTextModels

/// Shared discovery validates labels without owning either workflow's content.
struct MeetingTopicDiscovery {
  static let maximumTopicsPerSlice = 4
  static let maximumTitleCharacters = 80
  private static let maximumCandidateTopics = 16
  let inference: NotesInference

  func titles(in source: MeetingTranscriptSlice) async throws -> [String] {
    let response = try await inference.response(
      GeneratedMeetingTopics.self, request: MeetingNotesPrompt.topics(source),
      format: .meetingTopics)
    return try Self.admittedTitles(response, in: source)
  }

  private static func admittedTitles(
    _ response: GeneratedMeetingTopics, in source: MeetingTranscriptSlice
  )
    throws -> [String]
  {
    guard response.topics.count <= maximumCandidateTopics else {
      throw TextModelError.invalidResponse
    }
    let sourceIdentity = MeetingTopicIdentity(source.text)
    var titles: [String] = []
    for value in response.topics {
      let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty, title.count <= maximumTitleCharacters else {
        throw TextModelError.invalidResponse
      }
      guard !title.contains(where: \.isNewline),
        MeetingTopicIdentity(title).sharesAnchor(with: sourceIdentity)
      else { continue }
      if !titles.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) {
        titles.append(title)
      }
    }
    return titles
  }
}
