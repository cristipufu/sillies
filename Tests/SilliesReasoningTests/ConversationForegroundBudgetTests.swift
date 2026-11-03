import Foundation
import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning

private actor ForegroundBudgetProbe: ConversationBudgeting {
  nonisolated let contextWindowTokens = 4_096
  nonisolated var conversationPolicy: ConversationPolicy { AppleConversationPolicy.conversation }
  nonisolated var generationProfile: TextGenerationProfile { AppleConversationPolicy.generation }
  private(set) var measurements = 0
  private(set) var maximumMessages = 0
  func inputTokenCount(_ request: TextGenerationRequest) throws -> Int {
    measurements += 1
    maximumMessages = max(maximumMessages, request.messages.count)
    return try ConversationTokenEstimate.count(request)
  }
}

@Test(arguments: [100, 10_000, 100_000])
func foregroundWorkIsBoundedIndependentlyOfConversationAge(messageCount: Int) async throws {
  let originals =
    (0..<messageCount).map {
      ChatMessage(role: $0.isMultiple(of: 2) ? .user : .companion, text: "Planning detail \($0).")
    } + [.init(role: .user, text: "What is next?")]
  let context = ChatContext(
    companionName: "Pogo", profile: .init(personality: "Curious"), messages: originals)
  let backend = ForegroundBudgetProbe()
  let prepared = try await ConversationContextManager(backend: backend, tools: []).prepare(context)
  #expect(prepared.messages.last == originals.last)
  #expect(prepared.messages.first?.role == .user)
  #expect(prepared.messages.count <= backend.conversationPolicy.history.recent.messageLimit)
  #expect(await backend.maximumMessages <= backend.conversationPolicy.history.recent.messageLimit)
  #expect(await backend.measurements <= 10)
  #expect(prepared.historyCoverage == .recentWindow)
  #expect(originals.count == messageCount + 1)
  #expect(prepared.memory == ConversationMemory())
}

@Test func aCompletedCheckpointDoesNotEvictVerbatimRecentContext() async throws {
  let recent: [ChatMessage] = [
    .init(role: .user, text: "Bring the blue folder, not the green one."),
    .init(role: .companion, text: "I will bring the blue folder."),
    .init(role: .user, text: "Which color did we agree on?"),
  ]
  let memory = ConversationMemory(
    summary: "We discussed preparation.", throughMessageID: recent[1].id)
  let context = ChatContext(
    companionName: "Pogo", profile: .init(personality: "Curious"), messages: recent, memory: memory)
  let prepared = try await ConversationContextManager(backend: ForegroundBudgetProbe(), tools: [])
    .prepare(context)
  #expect(prepared.messages == recent)
  #expect(prepared.memory == memory)
}

@Test func largeStoredMemoryIsNotRewrittenWhenOnlyTheNewestTurnFits() async throws {
  let history =
    (0..<20).flatMap { _ in
      [
        ChatMessage(role: .user, text: String(repeating: "Source detail. ", count: 100)),
        ChatMessage(role: .companion, text: "Understood."),
      ]
    } + [.init(role: .user, text: "Continue")]
  let memory = ConversationMemory(
    summary: String(repeating: "An earlier fact. ", count: 100), throughMessageID: UUID())
  let context = ChatContext(
    companionName: "Pogo", profile: .init(personality: "Curious"), messages: history, memory: memory
  )
  let backend = ForegroundBudgetProbe()
  let prepared = try await ConversationContextManager(backend: backend, tools: []).prepare(context)
  #expect(context.memory == memory)
  #expect(prepared.messages.last == history.last)
  #expect(await backend.measurements <= 10)
  let request = ChatReplyGenerator.request(
    for: prepared, tools: [], maximumTokens: backend.generationProfile.conversation.outputTokens)
  #expect(try await ConversationBudget(backend: backend).admits(request))
}

@Test func oversizedHistoricalToolEvidenceCannotDisplaceTheLatestQuestion() async throws {
  let exchange = ConversationToolExchange(
    call: .init(id: "old", name: "search_vault", arguments: Data("{}".utf8)),
    result: String(repeating: "Large old evidence. ", count: 10_000))
  let current = ChatMessage(role: .user, text: "Tell me something new.")
  let context = ChatContext(
    companionName: "Pogo", profile: .init(personality: "Curious"),
    messages: [
      .init(role: .user, text: "Old question"),
      .init(role: .companion, text: "Old answer", evidence: .init(exchanges: [exchange])), current,
    ])
  let prepared = try await ConversationContextManager(backend: ForegroundBudgetProbe(), tools: [])
    .prepare(context)
  #expect(prepared.messages == [current])
  #expect(context.messages[1].exchanges == [exchange])
}
