import Foundation
import SilliesTextModels

/// Every displayed passage comes from the source. Inference proposes only subject labels.
struct MeetingExcerptDraft: MeetingNotesDraft {
  private let inference: NotesInference
  private var catalog = MeetingExcerptCatalog()
  private let personalNotes: String
  var actionLanguageIdentifier: String? { nil }
  init(personalNotes: String, inference: NotesInference) {
    self.personalNotes = personalNotes
    self.inference = inference
  }

  mutating func append(_ source: MeetingTranscriptSlice) async throws {
    let discovered = try await MeetingTopicDiscovery(inference: inference).titles(in: source)
    let titles = discovered.compactMap { title in
      source.text.range(of: title, options: [.caseInsensitive, .diacriticInsensitive])
        .map { String(source.text[$0]) }
    }
    let material = MeetingTopicEvidence.Source(
      source, topicTitles: catalog.topics.map(\.title) + titles)
    for topic in catalog.topics { catalog.append(material.matching(topic.title), to: topic) }
    let resolver = MeetingTopicResolver(inference: inference)
    for title in titles {
      if try await resolver.match(title, in: catalog.topics) != nil { continue }
      catalog.insert(title: title, evidence: material.matching(title))
    }
  }

  func finish(actions: [String]) async throws -> LocalNotes {
    guard !catalog.topics.isEmpty else { throw TextModelError.invalidResponse }
    return LocalNotes(
      summary: catalog.text(emphasizing: personalNotes), actions: actions,
      provenance: .init(source: .extracted))
  }
}
