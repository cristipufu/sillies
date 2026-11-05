import Foundation
import FoundationModels
import SilliesCore
import SilliesTextModels
import Synchronization
import Testing

@testable import SilliesReasoning

@Test func nativeToolSchemasPreserveOptionalContinuationParameters() throws {
  let definition = ConversationToolDefinition(
    name: "read_record", description: "Read a bounded passage",
    parameters: [
      .init("recordID", description: "Saved ID"),
      .init("offset", description: "Continue reading", kind: .integer, requirement: .optional),
    ])
  let restored = try JSONDecoder().decode(
    ConversationToolDefinition.self, from: JSONEncoder().encode(definition))
  #expect(restored == definition)
  let tool = try AppleConversationTool(definition, invoke: { _ in "A bounded passage" })
  let schema = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(tool.parameters)) as? [String: Any])
  #expect(schema["required"] as? [String] == ["recordID"])
  let properties = try #require(schema["properties"] as? [String: Any])
  #expect(properties["offset"] != nil)
}

private actor ConversationProbe: ConversationBackend {
  nonisolated let contextWindowTokens = 4_096
  func inputTokenCount(_ request: TextGenerationRequest) throws -> Int {
    try ConversationTokenEstimate.count(request)
  }
  nonisolated var conversationPolicy: ConversationPolicy { AppleConversationPolicy.conversation }
  nonisolated var generationProfile: TextGenerationProfile { AppleConversationPolicy.generation }
  var request: TextGenerationRequest?
  func availabilityNotice(localeIdentifier: String?) -> String? { nil }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) throws -> String {
    Issue.record("Chat must use the native conversation capability")
    throw TextModelError.invalidResponse
  }
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) -> String {
    self.request = request
    return "Mount Everest."
  }
}

@Test func chatKeepsRolesAndSendsTheLatestQuestionExactlyOnce() async throws {
  let backend = ConversationProbe()
  let service = LocalConversationService(resolveBackend: { backend }, tools: [], turns: .init())
  let messages: [ChatMessage] = [
    .init(role: .user, text: "How old are you?"),
    .init(role: .companion, text: "I'm a fictional window companion."),
    .init(role: .user, text: "What's the tallest mountain in the world?"),
  ]
  _ = try await service.reply(
    to: .init(companionName: "Pogo", profile: .init(personality: "Curious"), messages: messages))
  let request = try #require(await backend.request)
  #expect(request.messages.map(\.role) == [.user, .assistant, .user])
  #expect(request.messages.map(\.content) == messages.map(\.text))
  let transcript = try AppleConversationTranscript.make(request)
  #expect(transcript.count == 3)
  guard case .prompt(let prompt) = transcript[1], case .response(let response) = transcript[2],
    case .text(let userText) = prompt.segments.first,
    case .text(let assistantText) = response.segments.first
  else {
    Issue.record("The Apple transcript must preserve native roles")
    return
  }
  #expect(userText.content == messages[0].text)
  #expect(assistantText.content == messages[1].text)
  #expect(request.prompt == messages.last?.text)
}

private actor SearchProbe: ConversationTool {
  nonisolated let definition = ConversationToolDefinition(
    name: "search", description: "Search", parameters: [])
  nonisolated let activity = "Searching"
  var calls = 0
  func call(arguments: Data) -> ConversationToolOutput {
    calls += 1
    return .init(text: "A real saved record")
  }
}

private actor GenerationProbe {
  var requests: [TextGenerationRequest] = []
  let call: ConversationToolCall
  init(call: ConversationToolCall) { self.call = call }
  func generate(_ request: TextGenerationRequest) -> TextGenerationOutput {
    requests.append(request)
    return requests.count == 1
      ? .init(text: "", calls: [call], reasoningContent: "Private turn state")
      : .init(text: "Found it.")
  }
}

@Test func downloadedChatReturnsToolResultsWithMatchingCallIDs() async throws {
  let tool = SearchProbe()
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  let call = ConversationToolCall(id: "call-1", name: "search", arguments: Data("{}".utf8))
  let generator = GenerationProbe(call: call)
  let request = TextGenerationRequest(
    conversation: .init(
      instructions: "Find saved items", messages: [.init(role: .user, content: "Find my meeting")],
      tools: [tool.definition]), maximumTokens: 240, style: .conversation)
  #expect(
    try await ConversationToolLoop.run(
      request, tools: toolbox,
      generate: { request, receive in
        let output = await generator.generate(request)
        if !output.text.isEmpty { try await receive(output.text) }
        return output
      }) == "Found it.")
  let followup = try #require(await generator.requests.last)
  #expect(followup.messages.map(\.role) == [.user, .assistant, .tool])
  #expect(followup.messages[1].calls == [call])
  #expect(followup.messages[1].reasoningContent == "Private turn state")
  #expect(TextMessage.exchanging(await toolbox.exchanges).allSatisfy { $0.reasoningContent == nil })
  #expect(followup.messages[2].callID == call.id)
  #expect(followup.messages[2].toolName == call.name)
  #expect(followup.messages[2].content == "A real saved record")
  #expect(await tool.calls == 1)
  #expect(await toolbox.exchanges.count == 1)
}

@Test func toolCallsStayBoundedAndUnknownNamesCannotReachTheStore() async throws {
  let tool = SearchProbe()
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  await #expect(throws: (any Error).self) {
    _ = try await toolbox.invoke(
      .init(id: "bad", name: "delete_records", arguments: Data("{}".utf8)))
  }
  #expect(await tool.calls == 0)
  for index in 0..<ConversationToolbox.maximumCalls {
    _ = try await toolbox.invoke(
      .init(id: "\(index)", name: "search", arguments: Data("{\"query\":\"\(index)\"}".utf8)))
  }
  for index in 0..<ConversationToolbox.maximumCalls {
    let refusal = try await toolbox.invoke(
      .init(id: "refused-\(index)", name: "search", arguments: Data("{}".utf8)))
    let result = try #require(
      JSONSerialization.jsonObject(with: Data(refusal.utf8)) as? [String: Any])
    #expect(result["status"] as? String == "notExecuted")
    #expect(result["remainingCalls"] as? Int == 0)
  }
  await #expect(throws: (any Error).self) {
    _ = try await toolbox.invoke(.init(id: "overflow", name: "search", arguments: Data("{}".utf8)))
  }
  #expect(await tool.calls == ConversationToolbox.maximumCalls)
}

@Test func nativeHistoryRetainsToolResults() async throws {
  let backend = ConversationProbe()
  let service = LocalConversationService(resolveBackend: { backend }, tools: [], turns: .init())
  let call = ConversationToolCall(id: "lookup", name: "search_vault", arguments: Data("{}".utf8))
  let exchange = ConversationToolExchange(call: call, result: "A saved meeting")
  let messages: [ChatMessage] = [
    .init(role: .user, text: "Find my meeting"),
    .init(role: .companion, text: "Found it", evidence: .init(exchanges: [exchange])),
    .init(role: .user, text: "Read that one"),
  ]
  let context = ChatContext(
    companionName: "Pogo", profile: .init(personality: "Curious"), messages: messages)
  #expect(context.messages.first?.text == "Find my meeting")
  _ = try await service.reply(to: context)
  let request = try #require(await backend.request)
  #expect(request.messages.map(\.role) == [.user, .assistant, .tool, .assistant, .user])
  let transcript = try AppleConversationTranscript.make(request)
  guard case .toolCalls(let calls) = transcript[2], case .toolOutput(let output) = transcript[3]
  else {
    Issue.record("Tool history must remain native transcript entries")
    return
  }
  #expect(calls.first?.id == call.id)
  #expect(output.id == call.id)
  #expect(output.toolName == call.name)
}

@Test func toolArgumentsRejectNonObjectsWithoutCrossingTheNativeJSONBoundary() async throws {
  let tool = SearchProbe()
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  for argument in ["null", "42", "\"bad\"", "[]", "{"] {
    await #expect(throws: (any Error).self) {
      _ = try await toolbox.invoke(.init(id: "bad", name: "search", arguments: Data(argument.utf8)))
    }
  }
  #expect(await tool.calls == 0)
}

private actor RecoveryTool: ConversationTool {
  nonisolated let definition = ConversationToolDefinition(
    name: "read", description: "Read", parameters: [])
  nonisolated let activity = "Reading"
  var calls = 0
  func call(arguments: Data) -> ConversationToolOutput {
    calls += 1
    return .init(text: "A detailed record passage", briefText: "A short passage")
  }
}

@Test func contextRecoveryReusesToolResultsWithoutRepeatingStorageReads() async throws {
  let tool = RecoveryTool()
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  let original = ConversationToolCall(id: "original", name: "read", arguments: Data("{}".utf8))
  #expect(try await toolbox.invoke(original) == "A detailed record passage")
  try await toolbox.beginRecovery()
  let retry = ConversationToolCall(id: "retry", name: "read", arguments: original.arguments)
  #expect(try await toolbox.invoke(retry) == "A short passage")
  #expect(await tool.calls == 1)
  #expect(await toolbox.exchanges.map(\.call.id) == [original.id, retry.id])
  await #expect(throws: (any Error).self) { try await toolbox.beginRecovery() }
}

@Test func streamedToolArgumentsStayOutOfTheUserFacingResponse() async throws {
  let tool = SearchProbe()
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  let call = ConversationToolCall(
    id: "call-stream", name: "search", arguments: Data("{\"query\":\"private lookup\"}".utf8))
  let generator = GenerationProbe(call: call)
  let received = Mutex("")
  let group = UUID()
  let request = TextGenerationRequest(
    conversation: .init(
      instructions: "Search", messages: [.init(role: .user, content: "Find my meeting")],
      tools: [tool.definition]), maximumTokens: 240, style: .conversation
  ).inConversation(group)
  let final = try await ConversationToolLoop.run(
    request, tools: toolbox, receive: { delta in received.withLock { $0 += delta } },
    generate: { request, receive in
      let output = await generator.generate(request)
      let text = output.calls.isEmpty ? "Found it." : "I'll look it up. "
      try await receive(text)
      return .init(text: text.trimmingCharacters(in: .whitespacesAndNewlines), calls: output.calls)
    })
  #expect(received.withLock { $0 } == "I'll look it up. \nFound it.")
  #expect(final == received.withLock { $0 })
  #expect(await generator.requests.allSatisfy { $0.conversationID == group })
}

@Test func interruptedDeliveryDoesNotImpersonateAssistantSpeechInHistory() {
  let reply = ChatMessage(role: .companion, text: "Here is the first part.")
    .withDelivery(.interrupted, spokenText: "Here is")
  let context = ChatContext(
    companionName: "Pogo", profile: .init(personality: "Curious"),
    messages: [
      .init(role: .user, text: "Explain"), reply, .init(role: .user, text: "Continue"),
    ])
  let request = ChatReplyGenerator.request(for: context, tools: [], maximumTokens: 240)
  #expect(request.messages.map(\.content) == context.messages.map(\.text))
  #expect(request.instructions.contains("were interrupted"))
  #expect(!request.messages.contains { $0.content.contains("Completed spoken phrases") })
  let complete = ChatContext(
    companionName: "Pogo", profile: context.profile,
    messages: [.init(role: .user, text: "Hello")])
  #expect(
    !ChatReplyGenerator.request(for: complete, tools: [], maximumTokens: 240).instructions.contains(
      "were interrupted"))
}

@Test func terminalToolRoundPreservesPublishedTextWithoutRepeatingTheOperation() async throws {
  let tool = SearchProbe()
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  let call = ConversationToolCall(id: "complete", name: "search", arguments: Data("{}".utf8))
  let generator = GenerationProbe(call: call)
  let received = Mutex("")
  let request = TextGenerationRequest(
    conversation: .init(
      instructions: "Chat", messages: [.init(role: .user, content: "Remember that")],
      tools: [tool.definition]), maximumTokens: 240, style: .conversation)
  let result = try await ConversationToolLoop.run(
    request, tools: toolbox, receive: { delta in received.withLock { $0 += delta } },
    generate: { request, receive in
      let output = await generator.generate(request)
      let text = output.calls.isEmpty ? "" : "Thanks, I'll remember that."
      if !text.isEmpty { try await receive(text) }
      return .init(text: text, calls: output.calls)
    })
  #expect(result == "Thanks, I'll remember that.")
  #expect(received.withLock { $0.trimmingCharacters(in: .whitespacesAndNewlines) } == result)
  #expect(await tool.calls == 1)
  #expect(await generator.requests.count == 2)
}

@Test func contextRecoveryReplaysEvidenceWithoutResettingTheExecutionAllowance() async throws {
  let tool = RecoveryTool()
  let toolbox = try ConversationToolbox(tools: [tool], progress: { _ in })
  for index in 0..<ConversationToolbox.maximumCalls {
    _ = try await toolbox.invoke(
      .init(id: "\(index)", name: "read", arguments: Data("{\"page\":\(index)}".utf8)))
  }
  try await toolbox.beginRecovery()
  let cached = try await toolbox.invoke(
    .init(id: "replay", name: "read", arguments: Data("{\"page\":0}".utf8)))
  #expect(cached == "A short passage")
  let refused = try await toolbox.invoke(
    .init(id: "extra", name: "read", arguments: Data("{\"page\":99}".utf8)))
  #expect(refused.contains("turnToolLimitReached"))
  #expect(await tool.calls == ConversationToolbox.maximumCalls)
}

@Test func chatAndTalkKeepOriginalRolesAndTheLatestUserPrompt() {
  let messages: [ChatMessage] = [
    .init(role: .user, text: "Explain jasmine tea."),
    .init(role: .companion, text: "Heat the water. Add the leaves.")
      .withDelivery(.interrupted, spokenText: "Heat the water."),
    .init(role: .user, text: "Continue"),
  ]
  let context = ChatContext(
    companionName: "Pogo", profile: .init(personality: "Curious"), messages: messages)
  let typed = ChatReplyGenerator.request(for: context, tools: [], maximumTokens: 240)
  let spoken = ChatReplyGenerator.request(
    for: context.presented(as: .talk), tools: [], maximumTokens: 240)
  #expect(typed.messages == spoken.messages)
  #expect(typed.messages.map(\.content) == messages.map(\.text))
  #expect(typed.messages.map(\.role) == [.user, .assistant, .user])
  #expect(
    typed.instructions.contains("Keep replies brief and speakable. Address the user as an adult."))
  #expect(!typed.instructions.contains("The user is speaking with you"))
  #expect(spoken.instructions.contains("The user is speaking with you"))
  #expect(spoken.instructions.contains("do not read out long URLs"))
}
