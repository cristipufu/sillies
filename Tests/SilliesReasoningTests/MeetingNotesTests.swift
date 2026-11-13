import Foundation
import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning

@Test func meetingTopicsCombineDistantDiscussionAndKeepLateCorrectionsAndActions() async throws {
  let backend = TopicNotesBackend()
  let source =
    "We proposed launching on May 9. Alice will test on Thursday. "
    + String(repeating: "Operational details were discussed. ", count: 360)
    + "The budget is 900 credits. "
    + String(repeating: "Operational details were discussed. ", count: 360)
    + "We agreed to move launch to May 11. Who owns support? Bob will review on Friday."
  let personalNotes = "Agenda: launch, budget, support. Acquisition approved?"
  let notes = await LocalReasoningService(backend: backend).notes(
    for: .init(
      source: source, kind: .listen, fallback: "Previous notes", personalNotes: personalNotes))
  #expect(notes.source == .generated)
  #expect(
    notes.summary.contains("launch\n• Agreed launch: May 11, superseding the May 9 proposal."))
  #expect(notes.summary.components(separatedBy: "launch\n").count == 2)
  #expect(notes.summary.contains("budget\n• The budget is 900 credits."))
  #expect(notes.summary.contains("support\n• Who owns support?"))
  #expect(!notes.summary.contains("Acquisition"))
  #expect(notes.actions == ["Alice will test on Thursday.", "Bob will review on Friday."])
  let requests = await backend.requests
  let discovery = requests.filter { $0.format == .meetingTopics }
  #expect(discovery.count > 2)
  let inputs = discovery.map { TopicSource(transcript: sourceTranscript($0.request.prompt)) }
  #expect(inputs.map(\.transcript).joined() == source)
  #expect(
    inputs.allSatisfy { $0.transcript.count <= MeetingTranscriptSlicer.maximumChunkCharacters })
  for item in requests.filter({ $0.format == .meetingTopicBody }) {
    let input = TopicWriting(item.request.prompt)
    #expect(input.personalNotes == personalNotes)
    #expect(input.latestTranscript.split(separator: "\n").allSatisfy { source.contains($0) })
  }
}

@Test func meetingTopicsPreserveIdentityAndOtherSubjectsWhileUpdatingARecurringSubject() throws {
  var catalog = MeetingTopicCatalog()
  catalog.save(title: "Launch", body: "Proposed: May 9.", replacing: nil)
  let original = try #require(catalog.topics.first(where: { $0.title == "Launch" }))
  catalog.save(title: "Budget", body: "900 credits.", replacing: nil)
  catalog.save(
    title: "Launch timing", body: "Agreed: May 11.",
    replacing: original)
  #expect(catalog.topics.count == 2)
  let updated = try #require(catalog.topics.first(where: { $0.title == "Launch" }))
  #expect(updated.id == original.id && updated.title == original.title)
  #expect(catalog.topics.first(where: { $0.title == "Budget" })?.body == "900 credits.")
  #expect(
    try catalog.text(titles: catalog.topics.map(\.title), bodies: catalog.topics.map(\.body))
      == "Launch\n• Agreed: May 11.\n\nBudget\n• 900 credits.")
}

@Test func meetingTopicAliasesCompareOnlyLabelsAndRejectInventedMatches() async throws {
  var catalog = MeetingTopicCatalog()
  for index in 0..<33 {
    catalog.save(
      title: "Subject \(index)", body: "Private body that is not needed for matching.",
      replacing: nil)
  }
  let backend = TopicNotesBackend()
  let inference = NotesInference(backend: backend, budgeting: backend, turns: .init())
  let matched = try await MeetingTopicResolver(inference: inference).match(
    "Subject alias", in: catalog.topics)
  #expect(matched?.title == "Subject 32")
  let requests = await backend.requests
  #expect(requests.count == 33)
  for item in requests {
    #expect(item.request.prompt.contains("'Subject alias'"))
    #expect(catalog.topics.contains { item.request.prompt.contains("'\($0.title)'?") })
    #expect(!item.request.prompt.contains("Private body"))
  }
  let invalid = TopicNotesBackend(scenario: .invalidMatch)
  await #expect(throws: (any Error).self) {
    try await MeetingTopicResolver(
      inference: .init(backend: invalid, budgeting: invalid, turns: .init())
    )
    .match("Subject alias", in: catalog.topics)
  }
}

@Test func meetingTopicsHonorTheSelectedContextBudgetWithoutDiscardingSourceTails() async throws {
  let backend = TopicNotesBackend(contextWindowTokens: 2_000)
  let source =
    "The budget is 900 credits. "
    + String(repeating: "Operational details were discussed. ", count: 90)
  let notes = await LocalReasoningService(backend: backend).notes(
    for: .init(source: source, kind: .record, fallback: "Earlier notes"))
  #expect(notes.source == .generated)
  let requests = await backend.requests
  let discovered = requests.filter { $0.format == .meetingTopics }.map {
    sourceTranscript($0.request.prompt)
  }
  #expect(
    discovered.count > 1
      && discovered.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        == source.trimmingCharacters(in: .whitespacesAndNewlines)
  )
  for item in requests {
    let shaped = TextGenerationRequest(
      instructions: item.request.instructions + "\n" + item.format.instruction,
      prompt: item.request.prompt, maximumTokens: item.request.maximumTokens)
    #expect(
      try await ConversationBudget(backend: backend).requiredTokens(shaped) <= 2_000 - 128 - 256)
  }
  let unavailable = TopicNotesBackend(contextWindowTokens: 512)
  let fallback = await LocalReasoningService(backend: unavailable).notes(
    for: .init(source: source, kind: .record, fallback: "Earlier notes"))
  #expect(fallback.source == .extracted && fallback.actions.isEmpty)
  #expect(await unavailable.requests.isEmpty)
}

@Test func meetingTopicEvidenceKeepsCorrectionsAndFollowingContextWithoutUnrelatedSubjects() {
  let source = MeetingTranscriptSlice(
    text: "We proposed launching on May 9. It remains tentative. The budget is 900 credits. "
      + "Support has no owner. We agreed to move launch to May 11.", offset: 120)
  let evidence = MeetingTopicEvidence.Source(source).matching("launch")
  #expect(evidence.text.contains("launching on May 9"))
  #expect(evidence.text.contains("It remains tentative."))
  #expect(evidence.text.contains("launch to May 11"))
  #expect(!evidence.text.contains("900") && !evidence.text.contains("Support"))
  #expect(evidence.range == source.range)
  let halves = evidence.halves()
  #expect(halves?.first.text.contains("May 9") == true)
  #expect(halves?.last.text.contains("May 11") == true)
}

@Test func meetingTopicMatchingNeverSubmitsDisjointSubjectsToTheModel() async throws {
  var catalog = MeetingTopicCatalog()
  catalog.save(title: "Marketing budget", body: "900 credits.", replacing: nil)
  let backend = TopicNotesBackend(scenario: .invalidMatch)
  let match = try await MeetingTopicResolver(
    inference: .init(backend: backend, budgeting: backend, turns: .init())
  ).match("Customer support", in: catalog.topics)
  #expect(match == nil)
  #expect(await backend.requests.isEmpty)
}

@Test func meetingTranscriptBoundariesPreserveWholeNumbersAndWords() throws {
  let source = "Budget 900.50 credits approved. Launch May 11."
  let prefix = try #require(
    MeetingTranscriptSlice.boundedPrefix(in: source[...], maximumCharacters: 12))
  #expect(prefix == "Budget ")
  let slice = MeetingTranscriptSlice(text: source, offset: 100)
  let halves = try #require(slice.halves())
  #expect(halves.first.text + halves.last.text == source)
  #expect(halves.first.range.upperBound == halves.last.range.lowerBound)
  #expect(halves.last.range.upperBound == slice.range.upperBound)
}

@Test func meetingTopicsNativeResponseBoundaryPreservesQuotesAndRejectsAmbiguousMatches() throws {
  #expect(
    AppleNotesText.items("• \"Ștefan trimite raportul la 14:30.\"\n- Alice will review tomorrow.")
      == ["Ștefan trimite raportul la 14:30.", "Alice will review tomorrow."])
  #expect(AppleNotesText.items("NONE").isEmpty)
  #expect(try AppleNotesText.decision(" YES\n").answer)
  #expect(try !AppleNotesText.decision("NO").answer)
  #expect(throws: TextModelError.self) { try AppleNotesText.decision("YES, but they differ") }
}

@Test func meetingTopicsRejectNumbersThatAppearOnlyInAnAgenda() async {
  let backend = TopicNotesBackend(scenario: .inventedBody)
  let notes = await LocalReasoningService(backend: backend).notes(
    for: .init(
      source: "The budget is 900 credits.", kind: .listen, fallback: "Previous notes",
      personalNotes: "Agenda: increase the budget to 950 credits?"))
  #expect(notes.source == .extracted)
  #expect(notes.actions.isEmpty)
  #expect(!notes.summary.contains("950"))
}

@Test(arguments: [MeetingNotesStyle.sourceExcerpts, .synthesized])
func meetingTopicsYieldBetweenRequestsAndCancellationReleasesInference(_ style: MeetingNotesStyle)
  async throws
{
  let gate = ReasoningTurnGate()
  let backend = SuspendedTopicBackend(style: style)
  let task = Task {
    await LocalReasoningService(backend: backend, turns: gate).notes(
      for: .init(source: "The budget is 900 credits.", kind: .record, fallback: "Previous notes"))
  }
  try await backend.waitForStart()
  let interactive = Task {
    try await gate.acquire(.interactive)
    await backend.markInteractive()
    await gate.release()
  }
  await Task.yield()
  await backend.finish()
  try await interactive.value
  let notes = await task.value
  switch style {
  case .sourceExcerpts:
    #expect(notes.source == .extracted && notes.notice.isEmpty)
    #expect(await backend.events == ["discover", "interactive", "actions"])
  case .synthesized:
    #expect(notes.source == .generated)
    #expect(await backend.events == ["discover", "interactive", "write", "actions"])
  }
  let cancelledBackend = SuspendedTopicBackend(style: style)
  let cancelled = Task {
    await LocalReasoningService(backend: cancelledBackend, turns: gate).notes(
      for: .init(source: "The budget is 900 credits.", kind: .record, fallback: "Previous notes"))
  }
  try await cancelledBackend.waitForStart()
  cancelled.cancel()
  await cancelledBackend.finish()
  let result = await cancelled.value
  #expect(result.summary == "Previous notes" && result.source != .generated)
  #expect(await cancelledBackend.events == ["discover"])
  #expect(await gate.tryAcquire())
  await gate.release()
}

private struct TopicSource: Decodable { let transcript: String }
private struct TopicWriting {
  let subject: String
  let earlierNotes: String
  let latestTranscript: String
  let personalNotes: String
  init(_ prompt: String) {
    let sections = prompt.components(separatedBy: "\nLatest transcript:\n")
    latestTranscript =
      sections.last ?? ""
    let context = (sections.first ?? "").components(
      separatedBy: "\nPersonal notes (emphasis only):\n")
    personalNotes = context.last ?? ""
    let earlier = (context.first ?? "").components(separatedBy: "\nEarlier notes:\n")
    earlierNotes = earlier.last ?? ""
    subject = (earlier.first ?? "").components(separatedBy: "\"").dropFirst().first ?? ""
  }
}

private actor TopicNotesBackend: NotesTestBackend {
  struct Request: Sendable {
    let request: TextGenerationRequest
    let format: ReasoningFormat
  }
  nonisolated let contextWindowTokens: Int
  enum Scenario { case valid, invalidMatch, inventedBody }
  private let scenario: Scenario
  private(set) var requests: [Request] = []
  init(contextWindowTokens: Int = 4_096, scenario: Scenario = .valid) {
    self.contextWindowTokens = contextWindowTokens
    self.scenario = scenario
  }
  func availabilityNotice(localeIdentifier: String?) -> String? { nil }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) throws -> String {
    requests.append(.init(request: request, format: format))
    switch format {
    case .meetingTopics:
      let source = sourceTranscript(request.prompt)
      var names: [String] = []
      if source.contains("launch") {
        names.append("launch")
      }
      if source.contains("900") { names.append("budget") }
      if source.contains("support") { names.append("support") }
      return try encoded(GeneratedMeetingTopics(topics: names))
    case .meetingTopicMatch:
      if scenario == .invalidMatch { return #"{"answer":"invalid"}"# }
      return try encoded(
        GeneratedReasoningDecision(
          answer: request.prompt.contains("'Subject alias'")
            && request.prompt.hasSuffix("'Subject 32'?")))
    case .meetingTopicBody:
      let input = TopicWriting(request.prompt)
      let body: String
      if scenario == .inventedBody {
        body = "The budget is 950 credits."
      } else if input.subject.lowercased() == "budget" {
        body = "The budget is 900 credits."
      } else if input.subject.lowercased() == "support" {
        body = "Who owns support?"
      } else if input.latestTranscript.contains("May 11") {
        body = "Agreed launch: May 11, superseding the May 9 proposal."
      } else {
        body = input.earlierNotes.isEmpty ? "Proposed launch: May 9." : input.earlierNotes
      }
      return try encoded(GeneratedMeetingTopicBody(body: body))
    case .actions:
      return try encoded(
        GeneratedActionEvidence(
          passages: [
            "Alice will test on Thursday.", "Bob will review on Friday.", "Who owns support?",
            "Invented will pay on Monday.",
          ].filter { request.prompt.contains($0) || $0.contains("Invented") }))
    case .actionReview:
      return try encoded(
        GeneratedReasoningDecision(
          answer: request.prompt.contains("Alice") || request.prompt.contains("Bob")))
    default: throw TextModelError.invalidResponse
    }
  }
}

private actor SuspendedTopicBackend: NotesTestBackend {
  nonisolated let meetingNotesStyle: MeetingNotesStyle
  init(style: MeetingNotesStyle) { meetingNotesStyle = style }
  private var continuation: CheckedContinuation<String, Never>?
  private(set) var events: [String] = []
  func availabilityNotice(localeIdentifier: String?) -> String? { nil }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> String {
    switch format {
    case .meetingTopics:
      events.append("discover")
      return await withCheckedContinuation { continuation = $0 }
    case .meetingTopicBody:
      events.append("write")
      return #"{"body":"The budget is 900 credits."}"#
    case .actions:
      events.append("actions")
      return #"{"passages":[]}"#
    default: throw TextModelError.invalidResponse
    }
  }
  func markInteractive() { events.append("interactive") }
  func finish() {
    continuation?.resume(returning: #"{"topics":["Budget"]}"#)
    continuation = nil
  }
  func waitForStart() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while continuation == nil, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(1))
    }
    try #require(continuation != nil)
  }
}

private func encoded(_ value: some Encodable) throws -> String {
  String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
}

private func sourceTranscript(_ prompt: String) -> String {
  prompt.components(separatedBy: "\nTranscript:\n").dropFirst().joined(separator: "\nTranscript:\n")
}

@Test func meetingTopicTranslationPreservesProtectedNumbersAndRejectsIncompleteOutput() async throws
{
  let source = ["The approved budget is 900 credits."]
  let changed = NotesTranslationBackend(.changedNumber)
  #expect(
    try await LocalNotesTranslation.translate(
      source, localeIdentifier: "fr",
      inference: .init(backend: changed, budgeting: changed, turns: .init())) == source)
  let valid = NotesTranslationBackend(.valid)
  #expect(
    try await LocalNotesTranslation.translate(
      source, localeIdentifier: "fr",
      inference: .init(backend: valid, budgeting: valid, turns: .init()))
      == ["Le budget approuvé est de 900 crédits."])
  let incomplete = NotesTranslationBackend(.incomplete)
  await #expect(throws: TextModelError.self) {
    try await LocalNotesTranslation.translate(
      source, localeIdentifier: "fr",
      inference: .init(backend: incomplete, budgeting: incomplete, turns: .init()))
  }
}

private struct NotesTranslationBackend: NotesTestBackend {
  enum Response { case valid, changedNumber, incomplete }
  let response: Response
  init(_ response: Response) { self.response = response }
  func availabilityNotice(localeIdentifier: String?) async -> String? { nil }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> String {
    switch response {
    case .valid: #"{"translations":["Le budget approuvé est de 900 crédits."]}"#
    case .changedNumber: #"{"translations":["Le budget approuvé est de 950 crédits."]}"#
    case .incomplete: #"{"translations":[]}"#
    }
  }
}
