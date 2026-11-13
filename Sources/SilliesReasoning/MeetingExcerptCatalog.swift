import Foundation

/// This catalog owns copied excerpts. It never accepts model-written bodies or translations.
struct MeetingExcerptCatalog: Sendable {
  struct Topic: MeetingTopicIdentifying {
    let id: UUID
    let title: String
    var selection: MeetingExcerptSelection
  }
  private(set) var topics: [Topic] = []

  mutating func insert(title: String, evidence: MeetingTopicEvidence) {
    guard !evidence.isEmpty else { return }
    var selection = MeetingExcerptSelection()
    selection.include(evidence)
    topics.append(.init(id: UUID(), title: title, selection: selection))
  }

  mutating func append(_ evidence: MeetingTopicEvidence, to topic: Topic) {
    guard let index = topics.firstIndex(where: { $0.id == topic.id }) else { return }
    topics[index].selection.include(evidence)
  }

  func text(emphasizing personalNotes: String) -> String {
    let focus = MeetingTopicIdentity(
      String(personalNotes.prefix(MeetingNotesPrompt.maximumPersonalNoteCharacters)))
    var emphasized: [Topic] = []
    var remaining: [Topic] = []
    for topic in topics {
      if MeetingTopicIdentity(topic.title).sharesAnchor(with: focus) {
        emphasized.append(topic)
      } else {
        remaining.append(topic)
      }
    }
    return (emphasized + remaining).map {
      MeetingNotesSection(title: $0.title, passages: $0.selection.passages).text
    }.joined(separator: "\n\n")
  }
}
