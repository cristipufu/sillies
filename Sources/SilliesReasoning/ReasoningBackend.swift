import Foundation
import SilliesTextModels

/// Shared tasks describe output shape; providers own their native inference mechanism.
package enum ReasoningFormat: Sendable {
  case text, notes, actions, actionReview, suggestion, translations, meetingTopics,
    meetingTopicMatch, meetingTopicBody
  var instruction: String {
    switch self {
    case .text: "Return only the requested text."
    case .notes:
      "Return ONLY a JSON object with string fields summary and explanation. Leave explanation empty unless requested."
    case .meetingTopics:
      "Return ONLY a JSON object with topics: [concise subject name strings]."
    case .meetingTopicMatch: "Return ONLY a JSON object with answer: true for yes or false for no."
    case .meetingTopicBody:
      "Return ONLY a JSON object with body: the updated plain notes paragraph."
    case .actions:
      "Return ONLY a JSON object with a passages array of verbatim complete transcript sentences."
    case .actionReview:
      "Return ONLY a JSON object with answer: true for an explicit future task with an actor, otherwise false."
    case .suggestion:
      "Return ONLY a JSON object with string fields question and evidence. Use empty strings when no question is warranted."
    case .translations:
      "Return ONLY a JSON object with a translations array of strings in input order."
    }
  }
}

package protocol ReasoningBackend: Sendable {
  var meetingNotesStyle: MeetingNotesStyle { get }
  func availabilityNotice(localeIdentifier: String?) async -> String?
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> String
}

extension ReasoningBackend {
  package var meetingNotesStyle: MeetingNotesStyle { .sourceExcerpts }
  func response<T: Decodable & Sendable>(
    _ type: T.Type, request: TextGenerationRequest, format: ReasoningFormat
  ) async throws -> T {
    let output = try await generate(request, format: format)
    return try JSONDecoder().decode(type, from: Data(output.utf8))
  }
}
