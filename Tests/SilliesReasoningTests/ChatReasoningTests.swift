import Foundation
import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning

private let reportedChatContext = ChatContext(
  companionName: "Pogo",
  profile: .init(
    personality: "Curious, bouncy and optimistic. Asks thoughtful little follow-up questions."),
  messages: [
    .init(role: .user, text: "hei wwhat's up"),
    .init(
      role: .companion,
      text: "Hi there! I'm Pogo, your little window companion. What's up with you today?"),
    .init(role: .user, text: "how old are you"),
  ])

@Test func chatRejectsReportedLoopAndRequestsConversationSampling() async throws {
  let backend = ChatBackendProbe()
  let service = LocalConversationService(resolveBackend: { backend }, tools: [], turns: .init())
  await #expect(throws: TextModelError.self) { try await service.reply(to: reportedChatContext) }
  #expect(await backend.style == .conversation)
}

private actor ChatBackendProbe: ConversationBackend {
  nonisolated let contextWindowTokens = 4_096
  func inputTokenCount(_ request: TextGenerationRequest) throws -> Int {
    try ConversationTokenEstimate.count(request)
  }
  nonisolated var conversationPolicy: ConversationPolicy { AppleConversationPolicy.conversation }
  nonisolated var generationProfile: TextGenerationProfile { AppleConversationPolicy.generation }
  var style: TextGenerationStyle?
  func availabilityNotice(localeIdentifier: String?) -> String? { nil }
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) async throws -> String
  { generate(request, format: .text) }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) -> String {
    style = request.style
    return String(repeating: "I'm 100% sure ", count: 40) + "I'm 10"
  }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_CHAT_MODEL_CHECK"] == "1"))
func appleChatHandlesTheReportedConversationWithoutRepeating() async throws {
  let service = LocalConversationService(
    resolveBackend: { AppleReasoningBackend() }, tools: [], turns: .init())
  let notice = await service.availabilityNotice(localeIdentifier: "en")
  try #require(notice == nil, "Apple model is unavailable: \(notice ?? "")")
  for _ in 0..<3 {
    let reply = try await service.reply(to: reportedChatContext)
    print("CHAT MODEL CHECK: \(reply)")
    #expect(!TextRepetitionGuard.containsLoop(reply.text))
    #expect(!reply.text.isEmpty)
  }
}
