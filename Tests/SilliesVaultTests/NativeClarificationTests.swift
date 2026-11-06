import Foundation
import SilliesCore
import Testing

@testable import SilliesReasoning
@testable import SilliesVault

/// A bounded native integration smoke check, not a model-quality score or broad tool-call benchmark.
@Test(
  .enabled(if: ProcessInfo.processInfo.environment["SILLIES_NATIVE_CLARIFICATION_CHECK"] == "1"))
func nativeAppleClarificationCompletesWithConversationTools() async throws {
  let backend = AppleReasoningBackend()
  let trace = NativeClarificationTrace()
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let vault = VaultLibrary(directory: directory.appendingPathComponent("Vault"))
  let conversations = ConversationLibrary(
    directory: directory.appendingPathComponent("Conversations"))
  let opened = try await conversations.open(.init(id: "pogo", name: "Pogo"))
  let history = ConversationHistoryTools(conversations: conversations, memories: conversations)
  #expect(await backend.availabilityNotice(localeIdentifier: "en") == nil)
  let service = LocalConversationService(
    resolveBackend: { backend },
    tools: [VaultSearchTool(library: vault), VaultReadTool(library: vault), trace], turns: .init(),
    history: .init(repository: nil, tools: { context in history.tools(for: context) }))
  let profile = CharacterChatProfile(personality: "Friendly and concise", languageIdentifier: "en")
  let baseline = LocalConversationService(
    resolveBackend: { backend },
    tools: [VaultSearchTool(library: vault), VaultReadTool(library: vault)], turns: .init(),
    history: .init(repository: nil, tools: { context in history.tools(for: context) }))
  let control = try await baseline.reply(
    to: ChatContext(
      companionName: "Pogo", profile: profile,
      messages: [.init(role: .user, text: "What is the tallest mountain above sea level?")]
    ).inHistory(opened.handle), progress: { _ in })
  print(
    "NATIVE CLARIFICATION baseline knowledge: \(control.text); tools: \(control.exchanges.map { $0.call.name })"
  )
  let direct = try await service.reply(
    to: ChatContext(
      companionName: "Pogo", profile: profile,
      messages: [.init(role: .user, text: "What is the tallest mountain above sea level?")]
    ).inHistory(opened.handle),
    progress: { _ in })
  #expect(direct.clarification == nil)
  // The matched control is diagnostic evidence, not an exact-output assertion: model choices vary.
  print(
    "NATIVE CLARIFICATION candidate knowledge: \(direct.text); tools: \(direct.exchanges.map { $0.call.name })"
  )
  let asked = try await service.reply(
    to: ChatContext(
      companionName: "Pogo", profile: profile,
      messages: [
        .init(
          role: .user,
          text:
            "I have two meetings: Monday planning and Friday review. Please ask me which one I mean using choices before we discuss it."
        )
      ]
    ).inHistory(opened.handle), progress: { _ in })
  let question = try #require(asked.clarification)
  #expect(question.choices.count >= 2 && !asked.text.isEmpty)
  print("NATIVE CLARIFICATION question: \(question.question); choices: \(question.choices)")
  await backend.stop()
}

private struct NativeClarificationTrace: ConversationTool {
  let base = ConversationClarificationTool()
  var definition: ConversationToolDefinition { base.definition }
  var activity: String { base.activity }
  func call(arguments: Data) throws -> ConversationToolOutput {
    print("NATIVE CLARIFICATION synthetic arguments: \(String(decoding: arguments, as: UTF8.self))")
    return try base.call(arguments: arguments)
  }
}
