import Foundation
import SilliesCore
import SilliesTextModels
import Synchronization
import Testing

@testable import SilliesReasoning

private let clarificationArguments = Data(
  #"{"question":"Which meeting?","first_choice":"Monday planning","second_choice":"Friday review"}"#
    .utf8)

@Test func clarificationEndsDownloadedGenerationAndDoesNotWaitForTheUser() async throws {
  let toolbox = try ConversationToolbox(
    tools: [ConversationClarificationTool()], progress: { _ in })
  let calls = Mutex(0)
  let text = Mutex("")
  let request = TextGenerationRequest(
    conversation: .init(
      instructions: "Ask when ambiguous.",
      messages: [.init(role: .user, content: "Discuss that meeting.")], tools: toolbox.definitions),
    maximumTokens: 100, style: .conversation)
  let answer = try await ConversationToolLoop.run(
    request, tools: toolbox, receive: { delta in text.withLock { $0 += delta } },
    generate: { _, _ in
      calls.withLock { $0 += 1 }
      return .init(
        text: "",
        calls: [.init(id: "ask", name: "request_clarification", arguments: clarificationArguments)]
          + (0..<6).map {
            .init(id: "later-\($0)", name: "unavailable", arguments: Data("{}".utf8))
          })
    })
  #expect(answer == "Which meeting?")
  #expect(text.withLock { $0 } == answer)
  #expect(calls.withLock { $0 } == 1)
  #expect(await toolbox.clarification?.choices == ["Monday planning", "Friday review"])
  #expect(await toolbox.remainingCalls == 0)
  #expect(await toolbox.exchanges.count == 1)
}

@Test func nativeClarificationRefusesLaterActionsAndKeepsTheOriginalQuestion() async throws {
  let action = ClarificationActionProbe()
  let toolbox = try ConversationToolbox(
    tools: [ConversationClarificationTool(), action], progress: { _ in })
  let invocation = AppleToolInvocation()
  await invocation.open(toolbox)
  await #expect(throws: ConversationClarificationRequested.self) {
    try await invocation.invoke(
      .init(id: "ask", name: "request_clarification", arguments: clarificationArguments))
  }
  let question = await toolbox.clarification
  let declined = try await toolbox.invoke(
    .init(id: "later", name: "action", arguments: Data("{}".utf8)))
  #expect(declined.contains("awaitingUserAnswer"))
  #expect(await action.calls == 0)
  #expect(await toolbox.clarification == question)
}

@Test(arguments: [
  #"{"question":"?","first_choice":"Same","second_choice":"Same"}"#,
  #"{"question":"","first_choice":"One","second_choice":"Two"}"#,
  #"{"question":"?","first_choice":42,"second_choice":"Two"}"#,
  #"{"question":"?","first_choice":"One"}"#,
]) func malformedClarificationRemainsAnArgumentFailure(_ json: String) async throws {
  let toolbox = try ConversationToolbox(
    tools: [ConversationClarificationTool()], progress: { _ in })
  let result = try await toolbox.invoke(
    .init(id: "bad", name: "request_clarification", arguments: Data(json.utf8)))
  #expect(result.contains("invalidArguments"))
  #expect(await toolbox.clarification == nil)
}

private actor ClarificationActionProbe: ConversationTool {
  nonisolated let definition = ConversationToolDefinition(
    name: "action", description: "A write", parameters: [])
  nonisolated let activity = "Writing"
  private(set) var calls = 0
  func call(arguments: Data) -> ConversationToolOutput {
    calls += 1
    return .init(text: "done")
  }
}
