import Foundation
import SilliesCore
import SilliesTextModels
import Synchronization
import Testing

@testable import SilliesReasoning

private actor ContextBackend: ConversationBackend {
  nonisolated var conversationPolicy: ConversationPolicy { AppleConversationPolicy.conversation }
  nonisolated let generationProfile: TextGenerationProfile
  enum Behavior { case succeeds, summaryFailure, overflowOnce, cancelMeasurement }
  let behavior: Behavior
  nonisolated let contextWindowTokens = 1_400
  var summaries: [TextGenerationRequest] = []
  var replies: [TextGenerationRequest] = []
  init(_ behavior: Behavior = .succeeds, reasoningTokenReserve: Int = 0) {
    self.behavior = behavior
    generationProfile = reasoningProfile(
      conversationTokens: reasoningTokenReserve, summaryTokens: reasoningTokenReserve)
  }
  func availabilityNotice(localeIdentifier: String?) -> String? { nil }
  func inputTokenCount(_ request: TextGenerationRequest) async throws -> Int {
    if behavior == .cancelMeasurement { throw CancellationError() }
    return
      (request.instructions.utf8.count + request.messages.reduce(0) { $0 + $1.content.utf8.count })
      / 4 + 64
  }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) throws -> String {
    summaries.append(request)
    if behavior == .summaryFailure { throw TextModelError.unavailable("Fixture summary failure") }
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

@Test func chatAdmissionReservesSpaceForMandatoryReasoning() async throws {
  let backend = ContextBackend(reasoningTokenReserve: 256)
  let service = LocalConversationService(resolveBackend: { backend }, tools: [], turns: .init())
  _ = try await service.reply(to: context(longHistory(turns: 10)))
  let final = try #require(await backend.replies.last)
  #expect(
    try await backend.inputTokenCount(final) + final.maximumTokens + backend.reasoningTokenReserve
      <= backend.contextWindowTokens)
  for summary in await backend.summaries {
    #expect(
      try await backend.inputTokenCount(summary) + summary.maximumTokens
        + backend.reasoningTokenReserve <= backend.contextWindowTokens)
  }
}

@Test func chatBoundsHundredsOfTurnsWithoutSummarizingOrDeletingOriginalHistory() async throws {
  let backend = ContextBackend()
  let service = LocalConversationService(resolveBackend: { backend }, tools: [], turns: .init())
  let history = longHistory(turns: 250)
  let reply = try await service.reply(to: context(history))
  let final = try #require(await backend.replies.last)
  #expect(history.count == 501)
  #expect(reply.memory == ConversationMemory())
  #expect(await backend.summaries.isEmpty)
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

@Test func chatUsesSavedMemoryAndReferencesWithoutInvokingAnUnavailableSummarizer() async throws {
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
  let memory = ConversationMemory(
    summary: "Ada owns the migration.", throughMessageID: history[1].id,
    references: [.init(id: source.id, title: source.title)])
  let reply = try await service.reply(to: context(history, memory: memory))
  #expect(await backend.summaries.isEmpty)
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
  #expect(reply.memory == ConversationMemory())
  #expect(await backend.summaries.isEmpty)
}

@Test func chatCancellationDuringMeasurementDoesNotPublishMemoryOrAnAnswer() async throws {
  let backend = ContextBackend(.cancelMeasurement)
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

private actor PartiallyDeliveredOverflow: ConversationBackend {
  nonisolated var conversationPolicy: ConversationPolicy { AppleConversationPolicy.conversation }
  nonisolated var generationProfile: TextGenerationProfile { AppleConversationPolicy.generation }
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
