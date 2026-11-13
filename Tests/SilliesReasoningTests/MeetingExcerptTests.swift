import Foundation
import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning

@Test func meetingExcerptsKeepOriginalWordingCorrectionsAndLanguageWithoutSynthesis() async throws {
  let backend = ExcerptNotesBackend(contextWindowTokens: 2_000)
  let source =
    "We proposed launching on May 9. That date is not final. Alice will test on Thursday. "
    + String(repeating: "Operational details were discussed. ", count: 120)
    + "The approved budget is 900 credits. "
    + String(repeating: "Operational details were discussed. ", count: 120)
    + "We agreed to move launch to May 11. Who owns support? Nobody has been assigned. Bob will review on Friday."
  let personalNotes = "Budget. Private agenda: Acquisition approved?"
  let notes = await LocalReasoningService(backend: backend).notes(
    for: .init(
      source: source, kind: .listen, fallback: "Previous notes", personalNotes: personalNotes,
      localeIdentifier: "fr"))
  #expect(notes.source == .extracted && notes.notice.isEmpty)
  #expect(notes.summary.hasPrefix("budget\n"))
  #expect(notes.summary.components(separatedBy: "launch\n").count == 2)
  #expect(notes.summary.contains("We proposed launching on May 9."))
  #expect(notes.summary.contains("We agreed to move launch to May 11."))
  #expect(notes.summary.contains("The approved budget is 900 credits."))
  #expect(notes.summary.contains("Nobody has been assigned."))
  #expect(!notes.summary.contains("Acquisition"))
  for line in notes.summary.split(separator: "\n") where line.hasPrefix("• ") {
    #expect(source.contains(line.dropFirst("• ".count)))
  }
  let early = try #require(notes.summary.range(of: "We proposed launching on May 9."))
  let late = try #require(notes.summary.range(of: "We agreed to move launch to May 11."))
  #expect(early.lowerBound < late.lowerBound)
  #expect(notes.actions == ["Alice will test on Thursday.", "Bob will review on Friday."])
  let requests = await backend.requests
  #expect(requests.filter { $0.format == .meetingTopics }.count > 2)
  #expect(!requests.contains { $0.format == .meetingTopicBody || $0.format == .translations })
  #expect(requests.allSatisfy { !$0.prompt.contains("Private agenda") })
  #expect(await backend.availabilityLocale == "en")
}

@Test func meetingExcerptSelectionBoundsContextWithoutClippingSentencesOrDuplicatingRanges() {
  let source =
    (0..<10).map { "Budget item \($0) was discussed." }.joined(separator: " ")
    + " The budget is 900 credits, but that proposal was rejected."
  let evidence = MeetingTopicEvidence.Source(.init(text: source, offset: 0)).matching("budget")
  var selection = MeetingExcerptSelection()
  selection.include(evidence)
  selection.include(evidence)
  #expect(selection.passages.count == MeetingExcerptSelection.maximumPassages)
  #expect(selection.passages.first == "Budget item 0 was discussed.")
  #expect(selection.passages.contains("Budget item 1 was discussed."))
  #expect(selection.passages.last == "The budget is 900 credits, but that proposal was rejected.")
  #expect(selection.passages.allSatisfy { source.contains($0) })
  let correction = "The final budget is 950 credits."
  selection.include(
    MeetingTopicEvidence.Source(.init(text: correction, offset: source.count)).matching("budget"))
  #expect(selection.passages.count == MeetingExcerptSelection.maximumPassages)
  #expect(selection.passages.first == "Budget item 0 was discussed.")
  #expect(selection.passages.last == correction)
}

@Test func meetingExcerptEvidenceMatchesSurfaceWordsAcrossContextDependentLemmas() {
  let source = MeetingTranscriptSlice(
    text: "Mina: Our approved marketing budget is 900 credits.", offset: 0)
  let evidence = MeetingTopicEvidence.Source(source).matching("marketing")
  #expect(evidence.text.contains("900"))
}

@Test func meetingExcerptContextStaysWithinItsSourceParagraph() {
  let source = MeetingTranscriptSlice(
    text:
      "Support ownership is unresolved.\nMarketing budget is 900 credits. We have not approved extra spending.",
    offset: 0)
  let material = MeetingTopicEvidence.Source(source)
  #expect(!material.matching("Support").text.contains("900"))
  #expect(material.matching("Marketing").text.contains("We have not approved extra spending."))
}

@Test func meetingExcerptContextDoesNotPullAnotherKnownSubjectIntoItsGroup() {
  let source = MeetingTranscriptSlice(
    text:
      "The marketing plan stays the same. The launch date is unresolved. Who owns customer follow-up? We have not assigned that task.",
    offset: 0)
  let material = MeetingTopicEvidence.Source(
    source, topicTitles: ["marketing", "launch", "customer follow-up"])
  #expect(!material.matching("marketing").text.contains("unresolved"))
  #expect(!material.matching("launch").text.contains("customer follow-up"))
  #expect(material.matching("customer follow-up").text.contains("We have not assigned that task."))
}

private actor ExcerptNotesBackend: NotesTestBackend {
  struct Request: Sendable {
    let format: ReasoningFormat
    let prompt: String
  }
  nonisolated var meetingNotesStyle: MeetingNotesStyle { .sourceExcerpts }
  nonisolated let contextWindowTokens: Int
  private(set) var availabilityLocale: String?
  private(set) var requests: [Request] = []
  init(contextWindowTokens: Int) { self.contextWindowTokens = contextWindowTokens }
  func availabilityNotice(localeIdentifier: String?) -> String? {
    availabilityLocale = localeIdentifier
    return nil
  }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) throws -> String {
    requests.append(.init(format: format, prompt: request.prompt))
    switch format {
    case .meetingTopics:
      let source = request.prompt.components(separatedBy: "\nTranscript:\n").dropFirst().joined(
        separator: "\nTranscript:\n")
      var topics = ["Acquisition approved"]
      if source.contains("launch") { topics.append("launch") }
      if source.contains("budget") { topics.append("budget") }
      if source.contains("support") { topics.append("support") }
      return try json(GeneratedMeetingTopics(topics: topics))
    case .meetingTopicMatch: return #"{"answer":false}"#
    case .actions:
      let candidates =
        [
          "Alice will test on Thursday.", "Bob will review on Friday.", "Who owns support?",
          "We agreed to move launch to May 11.",
        ]
        .filter { request.prompt.contains($0) } + ["An invented person will send money."]
      return try json(GeneratedActionEvidence(passages: candidates))
    case .actionReview:
      return try json(
        GeneratedReasoningDecision(
          answer: request.prompt.contains("Alice") || request.prompt.contains("Bob")))
    default: throw TextModelError.invalidResponse
    }
  }
  private func json(_ value: some Encodable) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
  }
}

@Test func meetingExcerptActionsReviewIndividualSentencesFromAQuotedParagraph() async {
  let source = "We agreed to ship the report on Friday. Alex will review the draft tomorrow."
  let backend = ParagraphActionBackend(source: source)
  let notes = await LocalReasoningService(backend: backend).notes(
    for: .init(source: source, kind: .record, fallback: "Existing notes"))
  #expect(notes.source == .extracted && notes.notice.isEmpty)
  #expect(notes.actions == ["Alex will review the draft tomorrow."])
}

private struct ParagraphActionBackend: NotesTestBackend {
  var meetingNotesStyle: MeetingNotesStyle { .sourceExcerpts }
  let source: String
  func availabilityNotice(localeIdentifier: String?) async -> String? { nil }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> String {
    switch format {
    case .meetingTopics: return #"{"topics":["report","draft"]}"#
    case .actions:
      let response = GeneratedActionEvidence(passages: [source])
      return String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
    case .actionReview:
      let quotation = request.prompt.components(separatedBy: "\n\n").last
      return quotation == "Alex will review the draft tomorrow."
        ? #"{"answer":true}"# : #"{"answer":false}"#
    default: throw TextModelError.invalidResponse
    }
  }
}
