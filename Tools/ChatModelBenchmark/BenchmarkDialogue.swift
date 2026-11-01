import Foundation
import SilliesCore
import SilliesTextModels

actor BenchmarkDialogue {
  private let scenario: BenchmarkScenario
  private let fixture: BenchmarkFixture
  private let session: UUID
  private var messages: [ChatMessage]
  private var memory = ConversationMemory()

  init(scenario: BenchmarkScenario, fixture: BenchmarkFixture, session: UUID) {
    self.scenario = scenario
    self.fixture = fixture
    self.session = session
    messages = scenario.history.map(\.chatMessage)
  }

  func prepare() async throws { try await fixture.save(messages, memory: memory) }

  func request(_ input: String) async throws -> ChatContext {
    let message = ChatMessage(role: .user, text: input)
    messages.append(message)
    try await fixture.save([message], memory: memory)
    return ChatContext(
      companionName: scenario.owner.name,
      profile: .init(
        personality: scenario.owner.personality, languageIdentifier: scenario.language),
      messages: messages, memory: memory
    ).inTurn(UUID(), session: session).inHistory(fixture.handle)
  }

  func accept(_ reply: ChatReply) async throws {
    memory = reply.memory
    let message = ChatMessage(
      role: .companion, text: reply.text,
      evidence: .init(sources: reply.sources, exchanges: reply.exchanges))
    messages.append(message)
    try await fixture.save([message], memory: memory)
  }

  func preserveInterrupted(_ text: String, progress: BenchmarkProgress.Snapshot) async throws {
    if let checkpoint = progress.memory { memory = checkpoint }
    guard !text.isEmpty || !progress.sources.isEmpty else {
      try await fixture.save([], memory: memory)
      return
    }
    let message = ChatMessage(
      role: .companion, text: text, evidence: .init(sources: progress.sources)
    ).withDelivery(.interrupted, spokenText: nil)
    messages.append(message)
    try await fixture.save([message], memory: memory)
  }
}
