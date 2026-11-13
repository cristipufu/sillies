import Foundation
import SilliesTextModels

/// One job owns these identities. A model can match a title but never allocate or replace an identity.
struct MeetingTopicCatalog: Sendable {
  struct Topic: MeetingTopicIdentifying {
    let id: UUID
    let title: String
    let body: String
  }
  private(set) var topics: [Topic] = []
  func text(titles: [String], bodies: [String]) throws -> String {
    guard titles.count == topics.count, bodies.count == topics.count else {
      throw TextModelError.invalidResponse
    }
    return zip(titles, bodies).map { title, body in
      MeetingNotesSection(title: title, passages: [body]).text
    }
    .joined(separator: "\n\n")
  }

  mutating func save(
    title: String, body: String, replacing original: Topic?
  ) {
    let topic = Topic(id: original?.id ?? UUID(), title: original?.title ?? title, body: body)
    if let index = topics.firstIndex(where: { $0.id == topic.id }) {
      topics[index] = topic
    } else {
      topics.append(topic)
    }
  }

}
