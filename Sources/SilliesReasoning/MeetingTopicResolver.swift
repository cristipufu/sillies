import Foundation

protocol MeetingTopicIdentifying: Identifiable, Sendable where ID == UUID {
  var title: String { get }
}

/// Each comparison contains two labels. Content and identity allocation remain with the catalog.
struct MeetingTopicResolver {
  let inference: NotesInference
  func match<Topic: MeetingTopicIdentifying>(_ title: String, in topics: [Topic]) async throws
    -> Topic?
  {
    if let exact = topics.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
      return exact
    }
    let identity = MeetingTopicIdentity(title)
    for topic in topics {
      guard identity.sharesAnchor(with: MeetingTopicIdentity(topic.title)) else { continue }
      try Task.checkCancellation()
      let result = try await inference.response(
        GeneratedReasoningDecision.self,
        request: MeetingNotesPrompt.match(title, to: topic.title), format: .meetingTopicMatch)
      if result.answer { return topic }
    }
    return nil
  }
}
