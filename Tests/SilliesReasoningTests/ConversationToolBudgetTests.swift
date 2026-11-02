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
  enum Completion { case answer, requestMoreTools }
  private let batchSize: Int
  private let completion: Completion
  private(set) var requests: [TextGenerationRequest] = []
  init(batchSize: Int, completion: Completion = .answer) {
    self.batchSize = batchSize
    self.completion = completion
  }
  func generate(_ request: TextGenerationRequest) -> TextGenerationOutput {
    requests.append(request)
    if request.tools.isEmpty, completion == .answer {
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
  let request = TextGenerationRequest(
    conversation: .init(
      instructions: "Find saved material.",
      messages: [.init(role: .user, content: "Find my notes")],
      tools: toolbox.definitions), maximumTokens: 240, style: .conversation)
  await #expect(throws: TextModelError.self) {
    try await ConversationToolLoop.run(
      request, tools: toolbox, generate: { request, _ in await generator.generate(request) })
  }
  #expect(await tool.calls == ConversationToolbox.maximumCalls)
  #expect(await toolbox.exchanges.count == ConversationToolbox.maximumCalls)
  #expect(await generator.requests.count == ConversationToolbox.maximumCalls + 1)
}

@Test(arguments: [1, 6])
func toolBudgetEndsWithAnAnswerRoundAndPreservesEveryCallResult(batchSize: Int) async throws {
  let tool = BudgetedSearch()
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  let generator = SearchingGenerator(batchSize: batchSize)
  let request = TextGenerationRequest(
    conversation: .init(
      instructions: "Find saved material.",
      messages: [.init(role: .user, content: "Find my notes")],
      tools: toolbox.definitions), maximumTokens: 240, style: .conversation)
  let answer = try await ConversationToolLoop.run(
    request, tools: toolbox,
    generate: { request, receive in
      let output = await generator.generate(request)
      if !output.text.isEmpty { try await receive(output.text) }
      return output
    })
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
