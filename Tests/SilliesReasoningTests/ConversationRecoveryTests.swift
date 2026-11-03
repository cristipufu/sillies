import Foundation
import SilliesCore
import SilliesTextModels
import Synchronization
import Testing

@testable import SilliesReasoning

@Test func protocolRecoveryReplaysCanonicalArgumentsButCannotExecuteNewOperations() async throws {
  let write = RecoveryWriteTool()
  let toolbox = try ConversationToolbox(tools: [write], progress: { _ in })
  let first = try await toolbox.invoke(
    .init(id: "first", name: "save", arguments: Data(#"{"key":"name","value":"Maren"}"#.utf8)))
  try await toolbox.beginReplay()
  let replay = try await toolbox.invoke(
    .init(id: "new-id", name: "save", arguments: Data(#"{"value":"Maren", "key":"name"}"#.utf8)))
  #expect(replay == first)
  let refused = try await toolbox.invoke(
    .init(id: "changed", name: "save", arguments: Data(#"{"key":"name","value":"Lior"}"#.utf8)))
  let result = try #require(
    JSONSerialization.jsonObject(with: Data(refused.utf8)) as? [String: Any])
  #expect(result["status"] as? String == "notExecuted")
  #expect(result["reason"] as? String == "recoveryReplayOnly")
  #expect(await write.writes == 1)
  await #expect(throws: (any Error).self) { try await toolbox.beginReplay() }
  await #expect(throws: (any Error).self) { try await toolbox.beginRecovery() }
}

@Test(arguments: RecoveryBackend.Behavior.allCases)
private func malformedChannelRecoveryIsBoundedAndNeverRepeatsAWrite(
  _ behavior: RecoveryBackend.Behavior
)
  async throws
{
  let backend = RecoveryBackend(behavior: behavior)
  let write = RecoveryWriteTool()
  let service = LocalConversationService(
    resolveBackend: { backend }, tools: [write], turns: .init())
  let context = ChatContext(
    companionName: "Pogo", profile: .init(personality: "Curious"),
    messages: [.init(role: .user, text: "Remember this preference.")])
  let delivered = Mutex("")
  do {
    let reply = try await service.streamReply(
      to: context, progress: { _ in }, receive: { delta in delivered.withLock { $0 += delta } })
    #expect(behavior == .once || behavior == .changedArguments)
    #expect(reply.text == "Remembered.")
    #expect(delivered.withLock { $0 } == reply.text)
  } catch {
    #expect(behavior != .once && behavior != .changedArguments)
    if behavior == .cancelled {
      #expect(error is CancellationError)
    } else {
      let failure = try #require(error as? TextGenerationFailure)
      #expect(
        failure.reason == (behavior == .tokenLimit ? .outputTokenLimit : .invalidReasoningBoundary))
    }
  }
  #expect(await write.writes == 1)
  let retried: [RecoveryBackend.Behavior] = [.once, .always, .changedArguments]
  #expect(await backend.attempts == (retried.contains(behavior) ? 2 : 1))
  if behavior == .afterText { #expect(delivered.withLock { $0 } == "Already delivered.") }
}

private actor RecoveryWriteTool: ConversationTool {
  nonisolated let definition = ConversationToolDefinition(
    name: "save", description: "A synthetic write", parameters: [])
  nonisolated let activity = "Saving"
  private(set) var writes = 0
  func call(arguments: Data) -> ConversationToolOutput {
    writes += 1
    return .init(text: "Saved")
  }
}

private actor RecoveryBackend: ConversationBackend {
  enum Behavior: CaseIterable {
    case once, always, afterText, cancelled, tokenLimit, changedArguments
  }
  let behavior: Behavior
  private(set) var attempts = 0
  nonisolated let contextWindowTokens = 8_192
  nonisolated var generationProfile: TextGenerationProfile { AppleConversationPolicy.generation }
  nonisolated var conversationPolicy: ConversationPolicy {
    .init(
      safetyTokens: 128, compaction: .init(summaryWords: 180, headroomTokens: 256),
      tools: .init(maximumCalls: 4, reserveTokens: 1_024, resultTokens: 256))
  }
  init(behavior: Behavior) { self.behavior = behavior }
  func availabilityNotice(localeIdentifier: String?) -> String? { nil }
  func inputTokenCount(_ request: TextGenerationRequest) -> Int { 100 }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) throws -> String {
    Issue.record("Recovery must not invoke an unrelated generation or summarize history.")
    throw TextModelError.invalidResponse
  }
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) async throws -> String
  {
    try await streamConversation(request, tools: tools, receive: { _ in })
  }
  func streamConversation(
    _ request: TextGenerationRequest, tools: ConversationToolbox,
    receive: @escaping TextDeltaSink
  ) async throws -> String {
    attempts += 1
    let arguments = behavior == .changedArguments && attempts > 1 ? "{\"value\":\"new\"}" : "{}"
    let result = try await tools.invoke(
      .init(id: "write-\(attempts)", name: "save", arguments: Data(arguments.utf8)))
    if behavior == .changedArguments && attempts > 1 {
      #expect(result.contains("recoveryReplayOnly"))
    }
    if behavior == .cancelled { throw CancellationError() }
    if behavior == .tokenLimit { throw TextGenerationFailure(reason: .outputTokenLimit) }
    if behavior == .afterText { try await receive("Already delivered.") }
    if attempts == 1 || (behavior != .once && behavior != .changedArguments) {
      throw TextGenerationFailure(reason: .invalidReasoningBoundary)
    }
    try await receive("Remembered.")
    return "Remembered."
  }
}
