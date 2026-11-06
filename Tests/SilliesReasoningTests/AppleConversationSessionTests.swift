import Foundation
import SilliesCore
import SilliesTextModels
import Synchronization
import Testing

@testable import SilliesReasoning

@Test func appleSessionReuseRequiresCommittedHistoryAndEndsWithItsOwner() async throws {
  let creations = Mutex(0)
  let sessions = AppleConversationSessions { _, _ in
    creations.withLock { $0 += 1 }
    return SessionFixture()
  }
  let lifetime = TextModelLifetime()
  await sessions.retain(for: lifetime)
  let first = sessionRequest([.init(role: .user, content: "Remember violet-42")], id: lifetime.id)
  let tools = try ConversationToolbox(tools: [], progress: { _ in })
  let answer = try await sessions.respond(first, tools: tools, receive: { _ in })
  let next = sessionRequest(
    first.messages + [
      .init(role: .assistant, content: answer), .init(role: .user, content: "Which code?"),
    ], id: lifetime.id)
  _ = try await sessions.respond(next, tools: tools, receive: { _ in })
  #expect(creations.withLock { $0 } == 1)
  // Repeating an earlier turn is a rewrite, not a continuation.
  _ = try await sessions.respond(first, tools: tools, receive: { _ in })
  #expect(creations.withLock { $0 } == 2)
  await lifetime.end()
  _ = try await sessions.respond(next, tools: tools, receive: { _ in })
  #expect(creations.withLock { $0 } == 3)
  await sessions.stop()
}

@Test func appleSessionFailureAndPressureNeverReuseMutableState() async throws {
  let creations = Mutex(0)
  let fail = SessionFailure()
  let sessions = AppleConversationSessions { _, _ in
    creations.withLock { $0 += 1 }
    return SessionFixture(fail: fail)
  }
  let lifetime = TextModelLifetime()
  await sessions.retain(for: lifetime)
  let tools = try ConversationToolbox(tools: [], progress: { _ in })
  let first = sessionRequest([.init(role: .user, content: "Hello")], id: lifetime.id)
  let answer = try await sessions.respond(first, tools: tools, receive: { _ in })
  let next = sessionRequest(
    first.messages + [
      .init(role: .assistant, content: answer), .init(role: .user, content: "Again"),
    ], id: lifetime.id)
  fail.value.withLock { $0 = true }
  await #expect(throws: CancellationError.self) {
    _ = try await sessions.respond(next, tools: tools, receive: { _ in })
  }
  fail.value.withLock { $0 = false }
  _ = try await sessions.respond(next, tools: tools, receive: { _ in })
  #expect(creations.withLock { $0 } == 2)
  await sessions.setRetention(.memoryPressure)
  let third = sessionRequest(
    next.messages + [
      .init(role: .assistant, content: answer), .init(role: .user, content: "Third"),
    ], id: lifetime.id)
  _ = try await sessions.respond(third, tools: tools, receive: { _ in })
  #expect(creations.withLock { $0 } == 3)
  await lifetime.end()
}

private struct SessionFixture: AppleChatSession {
  let fail: SessionFailure
  init(fail: SessionFailure = SessionFailure()) { self.fail = fail }
  func respond(_ request: TextGenerationRequest, receive: @escaping TextDeltaSink) async throws
    -> String
  {
    if fail.value.withLock({ $0 }) { throw CancellationError() }
    try await receive("violet-42")
    return "violet-42"
  }
}
private func sessionRequest(_ messages: [TextMessage], id: UUID) -> TextGenerationRequest {
  TextGenerationRequest(
    conversation: .init(instructions: "Remember the code", messages: messages, tools: []),
    maximumTokens: 40, style: .precise
  ).inSession(id)
}

private final class SessionFailure: Sendable { let value = Mutex(false) }

@Test func appleRetainedToolsUseCurrentTurnAndPreserveCommittedNativeToolHistory() async throws {
  let routers = Mutex<[AppleToolInvocation]>([])
  let sessions = AppleConversationSessions { _, router in
    routers.withLock { $0.append(router) }
    return ToolSessionFixture(invocation: router)
  }
  let lifetime = TextModelLifetime()
  await sessions.retain(for: lifetime)
  let firstTool = TurnTool(value: "first-turn")
  let secondTool = TurnTool(value: "second-turn")
  func request(_ messages: [TextMessage]) -> TextGenerationRequest {
    .init(
      conversation: .init(
        instructions: "Use lookup when asked", messages: messages,
        tools: [firstTool.definition]), maximumTokens: 40, style: .precise
    ).inSession(lifetime.id)
  }
  let first = request([.init(role: .user, content: "Hello")])
  let response = try await sessions.respond(
    first,
    tools: .init(tools: [firstTool], progress: { _ in }), receive: { _ in })
  let second = request(
    first.messages + [
      .init(role: .assistant, content: response),
      .init(role: .user, content: "lookup"),
    ])
  let secondToolbox = try ConversationToolbox(tools: [secondTool], progress: { _ in })
  let answer = try await sessions.respond(second, tools: secondToolbox, receive: { _ in })
  #expect(answer == "second-turn")
  #expect(routers.withLock { $0.count } == 1)
  let router = try #require(routers.withLock { $0.first })
  await #expect(throws: TextModelError.self) {
    _ = try await router.invoke(.init(id: "late", name: "lookup", arguments: Data("{}".utf8)))
  }
  let exchanges = await secondToolbox.exchanges
  let third = request(
    second.messages + TextMessage.exchanging(exchanges) + [
      .init(role: .assistant, content: answer),
      .init(role: .user, content: "Hello again"),
    ])
  _ = try await sessions.respond(
    third,
    tools: .init(tools: [secondTool], progress: { _ in }), receive: { _ in })
  #expect(routers.withLock { $0.count } == 1)
  // A changed tool result is a different history and must rebuild the native session.
  let changed = request(
    second.messages
      + TextMessage.exchanging([
        .init(call: exchanges[0].call, result: "Changed result")
      ]) + [
        .init(role: .assistant, content: answer), .init(role: .user, content: "Hello again"),
      ])
  _ = try await sessions.respond(
    changed,
    tools: .init(tools: [secondTool], progress: { _ in }), receive: { _ in })
  #expect(routers.withLock { $0.count } == 2)
  await lifetime.end()
}

private struct ToolSessionFixture: AppleChatSession {
  let invocation: AppleToolInvocation
  func respond(_ request: TextGenerationRequest, receive: @escaping TextDeltaSink) async throws
    -> String
  {
    if request.prompt == "lookup" {
      return try await invocation.invoke(
        .init(id: "call", name: "lookup", arguments: Data("{}".utf8)))
    }
    return "Hello"
  }
}
private struct TurnTool: ConversationTool {
  let value: String
  let definition = ConversationToolDefinition(name: "lookup", description: "Read", parameters: [])
  let activity = "Reading"
  func call(arguments: Data) async throws -> ConversationToolOutput { .init(text: value) }
}

@Test func appleClarificationRebuildsNativeStateWhileKeepingTheCanonicalConversation() async throws
{
  let creations = Mutex(0)
  let sessions = AppleConversationSessions { _, invocation in
    creations.withLock { $0 += 1 }
    return ClarificationSessionFixture(invocation: invocation)
  }
  let lifetime = TextModelLifetime()
  await sessions.retain(for: lifetime)
  let tool = ConversationClarificationTool()
  func request(_ messages: [TextMessage]) -> TextGenerationRequest {
    .init(
      conversation: .init(
        instructions: "Clarify ambiguity", messages: messages, tools: [tool.definition]),
      maximumTokens: 100, style: .conversation
    ).inSession(lifetime.id)
  }
  let first = request([.init(role: .user, content: "Ask")])
  let tools = try ConversationToolbox(tools: [tool], progress: { _ in })
  let answer = try await sessions.respond(first, tools: tools, receive: { _ in })
  let exchanges = await tools.exchanges
  #expect(await tools.clarification != nil && exchanges.count == 1)
  let next = request(
    first.messages + TextMessage.exchanging(exchanges) + [
      .init(role: .assistant, content: answer), .init(role: .user, content: "Planning"),
    ])
  let followup = try await sessions.respond(
    next, tools: .init(tools: [tool], progress: { _ in }), receive: { _ in })
  #expect(creations.withLock { $0 } == 2)
  #expect(followup == "Planning")
  await lifetime.end()
}

private struct ClarificationSessionFixture: AppleChatSession {
  let invocation: AppleToolInvocation
  func respond(_ request: TextGenerationRequest, receive: @escaping TextDeltaSink) async throws
    -> String
  {
    guard request.prompt == "Ask" else { return request.prompt }
    do {
      return try await invocation.invoke(
        .init(
          id: "question", name: ConversationClarificationTool.name,
          arguments: Data(
            #"{"question":"Which meeting?","first_choice":"Planning","second_choice":"Review"}"#
              .utf8)))
    } catch let requested as ConversationClarificationRequested {
      return requested.question.question
    }
  }
}
