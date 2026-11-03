import Foundation
import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning
@testable import SilliesVault

private actor WorkingHistoryBackend: ConversationBackend {
  nonisolated let contextWindowTokens = 16_384
  nonisolated var conversationPolicy: ConversationPolicy { AppleConversationPolicy.conversation }
  nonisolated var generationProfile: TextGenerationProfile { AppleConversationPolicy.generation }
  private(set) var request: TextGenerationRequest?
  func availabilityNotice(localeIdentifier: String?) -> String? { nil }
  func inputTokenCount(_ request: TextGenerationRequest) throws -> Int {
    try ConversationTokenEstimate.count(request)
  }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) throws -> String {
    Issue.record("This short history fits the selected context without summarization")
    throw TextModelError.invalidResponse
  }
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) -> String {
    self.request = request
    return "Ready"
  }
}

enum WorkingHistoryCheckpoint: Sendable, CaseIterable { case absent, saved }

@Test(arguments: WorkingHistoryCheckpoint.allCases)
func agentReadsABoundedArchiveWindowAndTheLatestDurableCheckpoint(
  checkpoint: WorkingHistoryCheckpoint
)
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let library = ConversationLibrary(directory: directory)
  let snapshot = try await library.open(.init(id: "pogo", name: "Pogo"))
  let messages =
    (0..<80).flatMap { index in
      [
        ChatMessage(role: .user, text: "Detail \(index)"),
        ChatMessage(role: .companion, text: "Noted \(index)"),
      ]
    } + [.init(role: .user, text: "Continue")]
  let checkpointIndex = 79
  let memory =
    checkpoint == .saved
    ? ConversationMemory(
      summary: "The earlier facts remain known.", throughMessageID: messages[checkpointIndex].id)
    : .init()
  try await library.save(
    .init(
      handle: snapshot.handle, messages: messages, checkpoint: .init(memory: memory), savedAt: .now)
  )
  if checkpoint == .saved {
    let expected = try await library.checkpoint(snapshot.handle)
    #expect(
      try await library.advanceCheckpoint(
        .init(
          handle: snapshot.handle, expected: expected, replacement: memory)))
  }
  let visible = try await library.page(.init(handle: snapshot.handle))
  #expect(visible.entries.count < messages.count)
  let backend = WorkingHistoryBackend()
  let service = LocalConversationService(
    resolveBackend: { backend }, tools: [], turns: .init(), history: .init(repository: library))
  let reply = try await service.reply(
    to: .init(
      companionName: "Pogo", profile: .init(personality: "Curious"),
      messages: visible.entries.map(\.message), memory: .init()
    ).inHistory(snapshot.handle))
  let request = try #require(await backend.request)
  var expected = Array(messages.suffix(backend.conversationPolicy.history.recent.messageLimit))
  if expected.first?.role == .companion { expected.removeFirst() }
  #expect(request.messages.map(\.content) == expected.map(\.text))
  #expect(reply.memory.throughMessageID == memory.throughMessageID)
  #expect(reply.memory.summary == memory.summary)
}
