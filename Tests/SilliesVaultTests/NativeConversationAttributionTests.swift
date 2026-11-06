import Foundation
import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning
@testable import SilliesVault

/// Native quality is reviewed from the emitted answers; assertions establish delivered inputs.
@Test(
  .enabled(if: ProcessInfo.processInfo.environment["SILLIES_ATTRIBUTION_CHECK"] == "1"),
  arguments: AttributionScenario.allCases)
func nativeConversationAttribution(_ scenario: AttributionScenario) async throws {
  var fixture = try await AttributionFixture.create(scenario)
  defer { fixture.remove() }
  try await fixture.run()
}

private struct AttributionFixture {
  let scenario: AttributionScenario
  let directory: URL
  let conversations: ConversationLibrary
  let handle: ConversationHandle
  let vault: VaultLibrary
  let memory: ConversationMemory
  var messages: [ChatMessage]

  static func create(_ scenario: AttributionScenario) async throws -> Self {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let conversations = ConversationLibrary(directory: directory)
    let snapshot = try await conversations.open(.init(id: "pogo", name: "Pogo"))
    let messages = scenario.history
    try await conversations.save(
      .init(
        handle: snapshot.handle, messages: messages, checkpoint: .init(), savedAt: .now))
    let first = try #require(messages.first)
    _ = try await conversations.remember(
      .init(
        handle: snapshot.handle, fact: .init(key: "name", value: "Alex"),
        source: .init(messageID: first.id, quote: first.text), savedAt: .now))
    return .init(
      scenario: scenario, directory: directory, conversations: conversations,
      handle: snapshot.handle,
      vault: VaultLibrary(directory: directory), memory: scenario.memory(messages),
      messages: messages)
  }

  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }

  mutating func run() async throws {
    let label = scenario.rawValue
    let backend = AppleReasoningBackend(
      conversations: AppleConversationSessions { request, invocation in
        print(
          "ATTRIBUTION INPUT \(label): \(String(decoding: try JSONEncoder().encode(request), as: UTF8.self))"
        )
        return try NativeAppleChatSession(request: request, invocation: invocation)
      })
    let lifetime = TextModelLifetime()
    await backend.retain(for: lifetime)
    do {
      for question in scenario.questions {
        try await ask(question, backend: backend, session: lifetime.id)
      }
      await lifetime.end()
      await backend.stop()
    } catch {
      await lifetime.end()
      await backend.stop()
      throw error
    }
  }

  private mutating func ask(_ question: String, backend: AppleReasoningBackend, session: UUID)
    async throws
  {
    let current = ChatMessage(role: .user, text: question)
    try await append(current)
    let context = ChatContext(
      companionName: "Pogo", profile: .init(personality: "Warm, curious and upbeat."),
      messages: messages, memory: memory
    ).inTurn(UUID(), session: session).inHistory(handle)
    let tools: [any ConversationTool] =
      [VaultSearchTool(library: vault), VaultReadTool(library: vault)]
      + ConversationHistoryTools(conversations: conversations, memories: conversations).tools(
        for: context)
    let prepared = try await ConversationContextManager(
      backend: backend, tools: tools.map(\.definition)
    )
    .prepare(context)
    let toolbox = try ConversationToolbox(tools: tools, progress: { _ in })
    let start = ContinuousClock.now
    let answer = try await ChatReplyGenerator.reply(to: prepared, backend: backend, tools: toolbox)
    let exchanges = await toolbox.exchanges
    #expect(prepared.messages.last?.id == current.id)
    try await append(.init(role: .companion, text: answer, evidence: .init(exchanges: exchanges)))
    print(
      "ATTRIBUTION OUTPUT \(scenario.rawValue): question=\(question); answer=\(answer); calls=\(exchanges.map { $0.call.name }); elapsed=\(start.duration(to: .now))"
    )
  }

  private mutating func append(_ message: ChatMessage) async throws {
    try await conversations.save(
      .init(handle: handle, messages: [message], checkpoint: .init(), savedAt: .now))
    messages.append(message)
  }
}

enum AttributionScenario: String, CaseIterable, Sendable {
  case clean
  case assistantError = "assistant-error"
  case summaryError = "summary-error"
  case assistantRefusal = "assistant-refusal"
  case summaryRefusal = "summary-refusal"

  var questions: [String] {
    switch self {
    case .assistantRefusal, .summaryRefusal:
      ["What is my name?", "And what is your name?"]
    case .clean, .assistantError, .summaryError:
      ["What's your name?", "No, you are Pogo. I am Alex.", "What is my name?"]
    }
  }

  var history: [ChatMessage] {
    let known: [ChatMessage] = [
      .init(role: .user, text: "My name is Alex."),
      .init(role: .companion, text: "Your name is Alex."),
    ]
    switch self {
    case .clean: return known
    case .assistantError, .summaryError:
      return known + [
        .init(role: .user, text: "What's your name?"),
        .init(role: .companion, text: "I'm Alex, your friendly window companion."),
      ]
    case .assistantRefusal, .summaryRefusal:
      return known + [
        .init(role: .user, text: "What is my name?"),
        .init(
          role: .companion,
          text: "I cannot disclose your personal information because I must respect your privacy."),
      ]
    }
  }

  func memory(_ messages: [ChatMessage]) -> ConversationMemory {
    switch self {
    case .clean, .assistantError, .assistantRefusal: .init()
    case .summaryError:
      .init(
        summary:
          "User facts: Alex. Decisions: Alex saved the user's name as Alex. Open questions: None.",
        throughMessageID: messages.last?.id, openingStatement: "Hello!")
    case .summaryRefusal:
      .init(
        summary:
          "The user's name is Alex. The assistant refuses to disclose the user's name due to privacy concerns.",
        throughMessageID: messages.last?.id, openingStatement: "Hello!")
    }
  }
}
