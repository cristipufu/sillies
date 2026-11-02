import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning

private actor CompactionWorkBackend: ConversationBackend {
  nonisolated let contextWindowTokens = 4_096
  nonisolated let reasoningTokenReserve = 1_024
  nonisolated let summaryReasoningReserve: Int
  private(set) var summaries: [TextGenerationRequest] = []

  init(summaryReasoningReserve: Int = 1_024) {
    self.summaryReasoningReserve = summaryReasoningReserve
  }

  nonisolated func reasoningTokenReserve(for style: TextGenerationStyle) -> Int {
    style == .summary ? summaryReasoningReserve : reasoningTokenReserve
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
  _ = try await ConversationCompactor(backend: backend).compact(messages, into: .init())
  let summaries = await backend.summaries
  #expect(summaries.count > 1)
  for summary in summaries {
    let required =
      try await backend.inputTokenCount(summary) + summary.maximumTokens
      + backend.reasoningTokenReserve(for: summary.style)
    #expect(required <= backend.contextWindowTokens)
  }
}

@Test func compactionUsesAvailableSourceCapacityInsteadOfRepeatedSmallSummaryCalls() async throws {
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
    backend: backend, tools: tools, progress: { _ in }
  ).prepare(original)

  let summaries = await backend.summaries
  #expect(!summaries.isEmpty)
  #expect(summaries.count <= 2)
  #expect(summaries.first?.prompt.contains("Turn 0:") == true)
  #expect(summaries.allSatisfy { !$0.prompt.contains(question.text) })
  #expect(prepared.messages.last?.id == question.id)
  #expect(prepared.messages.first?.role == .user)
  #expect(prepared.messages.count > 1)
  #expect(original.messages.count == history.count + 1)
  for summary in summaries {
    #expect(
      try await backend.inputTokenCount(summary) + summary.maximumTokens
        + backend.reasoningTokenReserve
        <= backend.contextWindowTokens)
  }
}
