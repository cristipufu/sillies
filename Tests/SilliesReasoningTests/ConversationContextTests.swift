import Foundation
import SilliesCore
import SilliesTextModels
import Synchronization
import Testing

@testable import SilliesReasoning

private actor ContextBackend: ConversationBackend {
  enum Behavior { case succeeds, summaryFailure, overflowOnce, cancelSummary }
  let behavior: Behavior
  nonisolated let contextWindowTokens = 1_400
  var summaries: [TextGenerationRequest] = []
  var replies: [TextGenerationRequest] = []
  init(_ behavior: Behavior = .succeeds) { self.behavior = behavior }
  func availabilityNotice(localeIdentifier: String?) -> String? { nil }
  func inputTokenCount(_ request: TextGenerationRequest) async throws -> Int {
    (request.instructions.utf8.count + request.messages.reduce(0) { $0 + $1.content.utf8.count })
      / 4 + 64
  }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) throws -> String {
    summaries.append(request)
    if behavior == .summaryFailure { throw TextModelError.unavailable("Fixture summary failure") }
    if behavior == .cancelSummary { throw CancellationError() }
    return "The user is Ada, prefers concise answers, and is planning the Aurora rollout."
  }
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) throws -> String {
    replies.append(request)
    if behavior == .overflowOnce, replies.count == 1 { throw TextModelError.contextLimit }
    return "We were planning the Aurora rollout, Ada."
  }
}

private func longHistory(turns: Int) -> [ChatMessage] {
  (0..<turns).flatMap { index in
    [
      ChatMessage(
        role: .user,
        text: "Turn \(index): My name is Ada. "
          + String(repeating: "We are planning the Aurora rollout. ", count: 6)),
      ChatMessage(
        role: .companion,
        text: "Turn \(index) acknowledged. "
          + String(repeating: "Let's consider the next step. ", count: 6)),
    ]
  } + [.init(role: .user, text: "What were we planning, and what's my name?")]
}
private func context(_ messages: [ChatMessage], memory: ConversationMemory = .init()) -> ChatContext
{
  .init(
    companionName: "Pogo", profile: .init(personality: "Curious"), messages: messages,
    memory: memory)
}

@Test func chatCompactsHundredsOfTurnsWithoutDroppingVisibleHistory() async throws {
  let backend = ContextBackend()
  let service = LocalConversationService(resolveBackend: { backend }, tools: [], turns: .init())
  let history = longHistory(turns: 250)
  let reply = try await service.reply(to: context(history))
  let final = try #require(await backend.replies.last)
  #expect(history.count == 501)
  #expect(reply.memory.summary.contains("Ada"))
  #expect(reply.memory.throughMessageID != nil)
  #expect(final.messages.last?.content == history.last?.text)
  #expect(final.messages.filter { $0.content == history.last?.text }.count == 1)
  #expect(final.messages.first?.role == .user)
  #expect(
    try await backend.inputTokenCount(final) + final.maximumTokens < backend.contextWindowTokens)
  #expect(final.messages.count < history.count)
  for request in await backend.summaries {
    #expect(request.tools.isEmpty)
    #expect(request.messages.first?.role == .user)
    #expect(!request.prompt.contains(history.last?.text ?? "missing"))
  }
  let before = await backend.summaries.count
  let continued =
    history + [.init(role: .companion, text: reply.text), .init(role: .user, text: "Thanks!")]
  _ = try await service.reply(to: context(continued, memory: reply.memory))
  #expect(await backend.summaries.count <= before + 1)
}

@Test func chatCompactionKeepsToolReferencesAndSurvivesSummaryFailure() async throws {
  let backend = ContextBackend(.summaryFailure)
  let header = SessionRecordHeader(
    SessionRecord(
      kind: .listen,
      origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Aurora"))))
  let source = ChatSource(header: header, excerpt: "Alex owns the migration.")
  var history = longHistory(turns: 8)
  history[1] = .init(
    role: .companion, text: "Found the meeting", evidence: .init(sources: [source]))
  let service = LocalConversationService(resolveBackend: { backend }, tools: [], turns: .init())
  let reply = try await service.reply(to: context(history))
  #expect(reply.memory.references.map(\.id) == [source.id])
  #expect(reply.memory.summary.contains("Ada"))
  #expect(reply.memory.summary.count <= ConversationMemory.maximumSummaryCharacters)
  #expect(!reply.text.isEmpty)
}

@Test func chatRecoversOnceFromProviderContextOverflowWithoutDuplicatingTheUserTurn() async throws {
  let backend = ContextBackend(.overflowOnce)
  let service = LocalConversationService(resolveBackend: { backend }, tools: [], turns: .init())
  let history = longHistory(turns: 2)
  let reply = try await service.reply(to: context(history))
  #expect(!reply.text.isEmpty)
  let requests = await backend.replies
  #expect(requests.count == 2)
  #expect(requests.last?.messages.count == 1)
  #expect(requests.last?.messages.last?.content == history.last?.text)
  #expect(reply.memory.throughMessageID == history.dropLast().last?.id)
}

@Test func chatCancellationDuringCompactionDoesNotPublishMemoryOrAnAnswer() async throws {
  let backend = ContextBackend(.cancelSummary)
  let updates = Mutex<[ConversationMemory]>([])
  let service = LocalConversationService(resolveBackend: { backend }, tools: [], turns: .init())
  await #expect(throws: CancellationError.self) {
    _ = try await service.reply(to: context(longHistory(turns: 20))) { update in
      if case .memory(let memory) = update { updates.withLock { $0.append(memory) } }
    }
  }
  #expect(updates.withLock { $0.isEmpty })
  #expect(await backend.replies.isEmpty)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_CHAT_MODEL_CHECK"] == "1"))
func appleChatCompactsNativeHistoryAndRecallsEarlierUserFacts() async throws {
  let backend = AppleReasoningBackend()
  try #require(await backend.availabilityNotice(localeIdentifier: "en") == nil)
  var history: [ChatMessage] = [
    .init(
      role: .user, text: "My name is Ada. Our project is called Aurora. I prefer concise answers."),
    .init(role: .companion, text: "I'll keep that in mind, Ada."),
  ]
  for index in 0..<24 {
    history += [
      .init(
        role: .user,
        text: "Planning step \(index): "
          + String(
            repeating:
              "We should review the proposal and ask the team for feedback before deciding on the schedule. ",
            count: 10)),
      .init(
        role: .companion,
        text: "Let's review the proposal, gather feedback, then agree on a schedule."),
    ]
  }
  history.append(.init(role: .user, text: "What's my name and what is our project called?"))
  let service = LocalConversationService(resolveBackend: { backend }, tools: [], turns: .init())
  let reply = try await service.reply(to: context(history)) { update in
    if case .memory(let value) = update { print("MEMORY UPDATE: \(value.summary.prefix(250))") }
  }
  print(
    "NATIVE CAPACITY: \(backend.contextWindowTokens). COMPACTION: \(reply.memory.summary); REPLY: \(reply.text)"
  )
  #expect(reply.memory.throughMessageID != nil)
  #expect(reply.text.contains("Ada"))
  #expect(reply.text.contains("Aurora"))
  #expect(history.count == 51)
}

private actor PartiallyDeliveredOverflow: ConversationBackend {
  nonisolated let contextWindowTokens = 8_192
  var calls = 0
  func availabilityNotice(localeIdentifier: String?) -> String? { nil }
  func inputTokenCount(_ request: TextGenerationRequest) -> Int { 300 }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) -> String { "Memory" }
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) throws -> String {
    throw TextModelError.contextLimit
  }
  func streamConversation(
    _ request: TextGenerationRequest, tools: ConversationToolbox, receive: @escaping TextDeltaSink
  ) async throws -> String {
    calls += 1
    try await receive("A reply already delivered. ")
    throw TextModelError.contextLimit
  }
}

@Test func contextOverflowAfterStreamingStartsNeverRegeneratesTheAlreadySpokenPrefix() async throws
{
  let backend = PartiallyDeliveredOverflow()
  let delivered = Mutex("")
  let service = LocalConversationService(resolveBackend: { backend }, tools: [], turns: .init())
  await #expect(throws: TextModelError.self) {
    try await service.streamReply(
      to: context([.init(role: .user, text: "Hello")]), progress: { _ in },
      receive: { delta in delivered.withLock { $0 += delta } })
  }
  #expect(await backend.calls == 1)
  #expect(delivered.withLock { $0 } == "A reply already delivered. ")
}
