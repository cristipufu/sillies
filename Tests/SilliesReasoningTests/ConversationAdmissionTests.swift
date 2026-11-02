import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning

private actor AdmissionBackend: ConversationBackend {
  nonisolated let contextWindowTokens = 4_096
  nonisolated let reasoningTokenReserve = 1_024
  private let measuredInput: Int
  private(set) var measurements = 0
  init(measuredInput: Int) { self.measuredInput = measuredInput }
  func availabilityNotice(localeIdentifier: String?) -> String? { nil }
  func inputTokenCount(_ request: TextGenerationRequest) -> Int {
    measurements += 1
    return measuredInput
  }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) throws -> String {
    Issue.record("A single user message has no historical turns to summarize")
    throw TextModelError.invalidResponse
  }
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) -> String { "Ready" }
}

private func admissionManager(_ backend: AdmissionBackend) -> ConversationContextManager {
  .init(
    backend: backend,
    tools: [.init(name: "lookup", description: "Search saved material", parameters: [])],
    progress: { _ in })
}

private func admissionContext() -> ChatContext {
  .init(
    companionName: "Pogo", profile: .init(personality: "Curious"),
    messages: [.init(role: .user, text: "Explain this concept")])
}

@Test(arguments: [1_623, 2_704])
func toolReserveDoesNotRejectASingleTurnThatFitsWithGenerationAndSafety(inputTokens: Int)
  async throws
{
  let backend = AdmissionBackend(measuredInput: inputTokens)
  let context = admissionContext()
  let prepared = try await admissionManager(backend).prepare(context)
  #expect(prepared.messages == context.messages)
  #expect(await backend.measurements == 1)
}

@Test(arguments: [-1, 2_705, Int.max])
func admissionRetainsSafetyAndRejectsInvalidlyLargeMeasuredCounts(inputTokens: Int) async {
  let backend = AdmissionBackend(measuredInput: inputTokens)
  await #expect(throws: TextModelError.self) {
    try await admissionManager(backend).prepare(admissionContext())
  }
  #expect(await backend.measurements == 1)
}
