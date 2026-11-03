import Foundation
import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning

@Test func nativeToolBudgetingDoesNotInterruptAnActiveProviderWithTokenMeasurement() async throws {
  let backend = AppleReasoningBackend()
  let budget = try await ConversationEvidenceBudget.prepare(
    backend: backend,
    request: .init(instructions: "", prompt: "A structured tool response", maximumTokens: 1))
  #expect(budget == nil)
  let toolbox = try ConversationToolbox(tools: [EvidenceTool()], progress: { _ in })
  try await toolbox.configure(evidence: budget, maximumCalls: 1)
  let call = ConversationToolCall(id: "first", name: "read", arguments: Data("{}".utf8))
  let result = try await toolbox.invoke(call)
  #expect(result.contains("source"))
  let declined = try await toolbox.invoke(call)
  #expect(declined.contains("turnToolLimitReached"))
}

private actor EvidenceTool: ConversationTool {
  nonisolated let definition = ConversationToolDefinition(
    name: "read", description: "Read", parameters: [])
  nonisolated let activity = "Reading"
  private(set) var calls = 0
  func call(arguments: Data) -> ConversationToolOutput {
    calls += 1
    return .init(
      text: "{\"excerpt\":\"" + String(repeating: "source ", count: 100) + "\"}",
      briefText: "{\"excerpt\":\"detail\",\"complete\":false}")
  }
}

@Test func toolEvidenceUsesCompleteRepresentationsWithinTheTurnBudget() async throws {
  let tool = EvidenceTool()
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  let budget = ConversationEvidenceBudget(
    totalTokens: 100, resultTokens: 50, measure: { $0.utf8.count })
  try await toolbox.configure(evidence: budget, maximumCalls: 2)
  let call = ConversationToolCall(id: "first", name: "read", arguments: Data("{}".utf8))
  let first = try await toolbox.invoke(call)
  let value = try #require(JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any])
  #expect(value["excerpt"] as? String == "detail")
  #expect(value["complete"] as? Bool == false)
  _ = try await toolbox.invoke(.init(id: "second", name: "read", arguments: call.arguments))
  #expect(await tool.calls == 1)
  #expect(await toolbox.remainingCalls == 0)
  #expect(await toolbox.exchanges.reduce(0) { $0 + $1.result.utf8.count } <= 100)
}

@Test func toolBudgetRefusesAnImpossibleResultWithoutReturningBrokenJSON() async throws {
  let budget = ConversationEvidenceBudget(
    totalTokens: 1, resultTokens: 1, measure: { $0.utf8.count })
  await #expect(throws: TextModelError.self) {
    try await budget.select(.init(text: "{\"answer\":42}"), remaining: 1)
  }
}

@Test func toolEvidenceMeasurementPropagatesCancellation() async {
  let budget = ConversationEvidenceBudget(
    totalTokens: 100, resultTokens: 100, measure: { _ in throw CancellationError() })
  await #expect(throws: CancellationError.self) {
    try await budget.select(.init(text: "A complete result"), remaining: 100)
  }
}

@Test func omissionNoticeStillRespectsTheIndividualResultAllowance() async {
  let budget = ConversationEvidenceBudget(
    totalTokens: 1_000, resultTokens: 1, measure: { $0.utf8.count })
  await #expect(throws: TextModelError.self) {
    try await budget.select(.init(text: "A result too large for its allowance"), remaining: 1_000)
  }
}
