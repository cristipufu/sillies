import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning

private actor CompactionWorkBackend: ConversationBackend {
  nonisolated var conversationPolicy: ConversationPolicy {
    .init(
      safetyTokens: 128, compaction: .init(summaryWords: 180, headroomTokens: 128),
      tools: .init(maximumCalls: 4, reserveTokens: 1_024, resultTokens: 768))
  }
  nonisolated let generationProfile: TextGenerationProfile
  nonisolated let contextWindowTokens = 4_096
  private(set) var summaries: [TextGenerationRequest] = []

  init(summaryReasoningReserve: Int = 1_024) {
    generationProfile = reasoningProfile(
      conversationTokens: 1_024, summaryTokens: summaryReasoningReserve)
  }

  func availabilityNotice(localeIdentifier: String?) -> String? { nil }
  func inputTokenCount(_ request: TextGenerationRequest) async throws -> Int {
    let promptOverhead = request.style == .conversation ? 1_200 : 200
    let body = request.messages.reduce(0) { $0 + $1.content.count }
    return promptOverhead + body / 4
  }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) -> String {
    summaries.append(request)
    return "The earlier conversation concerns a launch checklist."
  }
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) -> String { "Ready" }
}

@Test func compactionAdmissionUsesTheSummaryTasksLargerReasoningAllowance() async throws {
  let backend = CompactionWorkBackend(summaryReasoningReserve: 2_048)
  let messages = (0..<24).flatMap { index in
    [
      ChatMessage(role: .user, text: "Detail \(index): " + String(repeating: "source ", count: 45)),
      ChatMessage(role: .companion, text: "Understood."),
    ]
  }
  let checkpoint = try #require(
    try await ConversationCompactor(backend: backend).compact(messages, into: .init()))
  #expect(checkpoint.throughMessageID != messages.last?.id)
  let summaries = await backend.summaries
  #expect(summaries.count == 1)
  for summary in summaries {
    let required =
      try await backend.inputTokenCount(summary) + summary.maximumTokens
      + backend.reasoningTokenReserve(for: summary.style)
    #expect(required <= backend.contextWindowTokens)
  }
}

@Test func foregroundPreparationNeverStartsCheckpointGeneration() async throws {
  let backend = CompactionWorkBackend()
  let history = (0..<40).flatMap { index in
    [
      ChatMessage(
        role: .user, text: "Turn \(index): " + String(repeating: "Source detail. ", count: 5)),
      ChatMessage(role: .companion, text: String(repeating: "Acknowledged. ", count: 5)),
    ]
  }
  let question = ChatMessage(role: .user, text: "What remains on our checklist?")
  let original = ChatContext(
    companionName: "Pogo", profile: .init(personality: "Curious"), messages: history + [question])
  let tools = [ConversationToolDefinition(name: "search", description: "Search", parameters: [])]
  let prepared = try await ConversationContextManager(
    backend: backend, tools: tools
  ).prepare(original)

  #expect(await backend.summaries.isEmpty)
  #expect(prepared.messages.last?.id == question.id)
  #expect(prepared.messages.first?.role == .user)
  #expect(original.messages.count == history.count + 1)
  #expect(
    try await backend.inputTokenCount(
      ChatReplyGenerator.request(
        for: prepared, tools: tools,
        maximumTokens: backend.generationProfile.conversation.outputTokens))
      + backend.generationProfile.conversation.outputTokens + backend.reasoningTokenReserve
      <= backend.contextWindowTokens)
}
