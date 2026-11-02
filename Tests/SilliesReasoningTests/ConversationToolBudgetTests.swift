import Foundation
import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning

private actor BudgetedSearch: ConversationTool {
  nonisolated let definition = ConversationToolDefinition(
    name: "search", description: "Find saved material", parameters: [])
  nonisolated let activity = "Searching"
  private(set) var calls = 0
  func call(arguments: Data) -> ConversationToolOutput {
    calls += 1
    return .init(text: "No matching records for this query.")
  }
}

private actor SearchingGenerator {
  enum Completion { case answer, answerAfterRefusal, requestMoreTools }
  private let batchSize: Int
  private let completion: Completion
  private(set) var requests: [TextGenerationRequest] = []
  init(batchSize: Int, completion: Completion = .answer) {
    self.batchSize = batchSize
    self.completion = completion
  }
  func stream(_ request: TextGenerationRequest, receive: TextDeltaSink) async throws
    -> TextGenerationOutput
  {
    let output = generate(request)
    if !output.text.isEmpty { try await receive(output.text) }
    return output
  }

  private func generate(_ request: TextGenerationRequest) -> TextGenerationOutput {
    requests.append(request)
    let receivedRefusal = request.messages.contains {
      $0.role == .tool && $0.content.contains("turnToolLimitReached")
    }
    if request.tools.isEmpty,
      completion == .answer || (completion == .answerAfterRefusal && receivedRefusal)
    {
      return .init(text: "No matching saved records were found.")
    }
    let calls = (0..<batchSize).map { index in
      let id = "\(requests.count)-\(index)"
      return ConversationToolCall(
        id: id, name: "search", arguments: Data("{\"query\":\"\(id)\"}".utf8))
    }
    return .init(text: "", calls: calls, reasoningContent: "Private turn state")
  }
}

@Test func answerOnlyRoundCannotExecuteAnUnadvertisedToolCall() async throws {
  let tool = BudgetedSearch()
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  let generator = SearchingGenerator(batchSize: 1, completion: .requestMoreTools)
  let request = searchRequest(tools: toolbox.definitions)
  await #expect(throws: TextModelError.self) {
    try await ConversationToolLoop.run(
      request, tools: toolbox,
      generate: { request, receive in try await generator.stream(request, receive: receive) })
  }
  #expect(await tool.calls == ConversationToolbox.maximumCalls)
  #expect(await toolbox.exchanges.count == ConversationToolbox.maximumCalls + 2)
  #expect(await generator.requests.count == ConversationToolbox.maximumCalls + 2)
}

@Test func refusedCompletionCallReceivesItsResultBeforeOneFinalAnswerAttempt() async throws {
  let tool = BudgetedSearch()
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  let generator = SearchingGenerator(batchSize: 1, completion: .answerAfterRefusal)
  let request = searchRequest(tools: toolbox.definitions)
  let answer = try await ConversationToolLoop.run(
    request, tools: toolbox,
    generate: { request, receive in try await generator.stream(request, receive: receive) })
  #expect(answer == "No matching saved records were found.")
  #expect(await tool.calls == ConversationToolbox.maximumCalls)
  let final = try #require(await generator.requests.last)
  #expect(final.tools.isEmpty)
  let refusal = try #require(final.messages.last)
  #expect(refusal.role == .tool)
  #expect(refusal.content.contains("notExecuted"))
  #expect(refusal.callID == final.messages.dropLast().last?.calls.first?.id)
  #expect(await generator.requests.count == ConversationToolbox.maximumCalls + 2)
}

@Test(arguments: [1, 6])
func toolBudgetEndsWithAnAnswerRoundAndPreservesEveryCallResult(batchSize: Int) async throws {
  let tool = BudgetedSearch()
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  let generator = SearchingGenerator(batchSize: batchSize)
  let request = searchRequest(tools: toolbox.definitions)
  let answer = try await ConversationToolLoop.run(
    request, tools: toolbox,
    generate: { request, receive in try await generator.stream(request, receive: receive) })
  #expect(answer == "No matching saved records were found.")
  #expect(await tool.calls == ConversationToolbox.maximumCalls)
  let final = try #require(await generator.requests.last)
  #expect(final.tools.isEmpty)
  let calls = final.messages.flatMap(\.calls)
  let results = final.messages.filter { $0.role == .tool }
  #expect(calls.map(\.id) == results.compactMap(\.callID))
  #expect(await toolbox.exchanges.count == calls.count)
  #expect(
    final.messages.last(where: { !$0.calls.isEmpty })?.reasoningContent == "Private turn state")
  #expect(await generator.requests.count <= ConversationToolbox.maximumCalls + 1)
}

@Test func nativeToolInvocationsReceiveABoundedLimitResultWithoutExecutingExtraCalls() async throws
{
  let tool = BudgetedSearch()
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  let invocation = AppleToolInvocation()
  await invocation.open(toolbox)
  for index in 0..<ConversationToolbox.maximumCalls {
    _ = try await invocation.invoke(
      .init(id: "\(index)", name: "search", arguments: Data("{\"query\":\"\(index)\"}".utf8)))
  }
  let response = try await invocation.invoke(
    .init(id: "overflow", name: "search", arguments: Data("{}".utf8)))
  #expect(response.contains("turnToolLimitReached"))
  #expect(await tool.calls == ConversationToolbox.maximumCalls)
  #expect(await toolbox.exchanges.last?.call.id == "overflow")
  await invocation.close()
}

private func searchRequest(tools: [ConversationToolDefinition]) -> TextGenerationRequest {
  .init(
    conversation: .init(
      instructions: "Find saved material.",
      messages: [.init(role: .user, content: "Find my notes")], tools: tools),
    maximumTokens: 240, style: .conversation)
}
