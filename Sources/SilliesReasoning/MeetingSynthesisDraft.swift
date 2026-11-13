import Foundation
import NaturalLanguage
import SilliesTextModels

/// Owns generated paragraphs; excerpt production never enters this synthesis workflow.
struct MeetingSynthesisDraft: MeetingNotesDraft {
  private let inference: NotesInference
  private var catalog = MeetingTopicCatalog()
  private let context: MeetingNotesPrompt.Context
  let actionLanguageIdentifier: String?
  init(_ request: LocalNotesRequest, inference: NotesInference) {
    self.inference = inference
    actionLanguageIdentifier = request.localeIdentifier
    context = .init(
      personalNotes: request.personalNotes,
      languageIdentifier: NLLanguageRecognizer.dominantLanguage(
        for: String(request.source.prefix(MeetingTranscriptSlicer.maximumChunkCharacters)))?
        .rawValue)
  }

  mutating func append(_ source: MeetingTranscriptSlice) async throws {
    let material = MeetingTopicEvidence.Source(source)
    let writer = MeetingTopicWriter(inference: inference)
    for existing in catalog.topics {
      let evidence = material.matching(existing.title)
      let body = try await writer.update(
        .init(title: existing.title, source: evidence, previous: existing.body, context: context))
      if body != existing.body {
        catalog.save(title: existing.title, body: body, replacing: existing)
      }
    }
    let titles = try await MeetingTopicDiscovery(inference: inference).titles(in: source)
    let resolver = MeetingTopicResolver(inference: inference)
    for title in titles {
      if try await resolver.match(title, in: catalog.topics) != nil { continue }
      let evidence = material.matching(title)
      let body = try await writer.update(
        .init(title: title, source: evidence, previous: "", context: context))
      if !body.isEmpty {
        catalog.save(title: title, body: body, replacing: nil)
      }
    }
  }

  func finish(actions: [String]) async throws -> LocalNotes {
    guard !catalog.topics.isEmpty else { throw TextModelError.invalidResponse }
    let titles = try await MeetingTopicTitleTranslator(inference: inference).titles(
      in: catalog, localeIdentifier: actionLanguageIdentifier)
    let bodies = try await LocalNotesTranslation.translate(
      catalog.topics.map(\.body), localeIdentifier: actionLanguageIdentifier, inference: inference)
    return try LocalNotes(
      summary: catalog.text(titles: titles, bodies: bodies), actions: actions,
      provenance: .init(
        source: .generated,
        notice: String(
          localized: "Generated on this Mac. Check the source before acting on these notes.")))
  }
}
