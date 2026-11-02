import Foundation
import FoundationModels
import SilliesCore
import SilliesPersistence
import SilliesTextModels
import Synchronization
import Testing

@testable import SilliesReasoning
@testable import SilliesVault

/// An opt-in comparison, not a claim that the installed model passes mixed-topic quality checks.
@Test(
  .enabled(if: ProcessInfo.processInfo.environment["SILLIES_APPLE_CHAT_COMPARISON"] == "1"),
  arguments: ["10000000-0000-4000-8000-000000000001", "10000000-0000-4000-8000-000000000002"])
func appleNativeAndApplicationTranscriptsUseIdenticalChatInputs(_ fixtureID: String) async throws {
  print("APPLE COMPARISON FIXTURE: \(fixtureID)")
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {
    do { try FileManager.default.removeItem(at: directory) } catch {
      Issue.record("Comparison fixture cleanup: \(error)")
    }
  }
  let library = VaultLibrary(directory: directory)
  var record = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Safari")),
    metadata: .init(
      id: try #require(UUID(uuidString: fixtureID)),
      createdAt: Date(timeIntervalSince1970: 1_793_534_400)))
  let savedURL = "https://example.com/project-aurora"
  record.stashedItems = [savedURL]
  _ = try await library.commit(.init(records: [.insert(record)]))
  let tools: [any ConversationTool] = [
    VaultSearchTool(library: library), VaultReadTool(library: library),
  ]
  let first = ChatMessage(role: .user, text: "Which URLs did I save?")
  let general = "Okay, tell me what's the tallest mountain in the world?"
  let request = comparisonRequest([first], tools: tools)
  let retained = try NativeChatComparison(seed: .instructions(request.instructions), tools: tools)
  let saved = try await retained.ask(first.text, label: "native first retrieval")
  let transcript = retained.session.transcript
  let messages = [
    first,
    ChatMessage(
      role: .companion, text: saved.text,
      evidence: .init(sources: saved.sources, exchanges: saved.exchanges)),
    .init(role: .user, text: general),
  ]
  let canonicalRequest = comparisonRequest(messages, tools: tools)
  let canonical = try AppleConversationTranscript.make(
    canonicalRequest,
    tools: retained.registered.map { .init(tool: $0) })
  print(
    "APPLE COMPARISON: canonical tool history retained=\(canonicalRequest.messages.filter { $0.role == .tool }.count), native entries=\(transcript.count), canonical entries=\(canonical.count)"
  )

  let freshPlain = try NativeChatComparison(seed: .instructions(request.instructions), tools: [])
  _ = try await freshPlain.ask(general, label: "fresh / no tools / app instructions")
  let freshTools = try NativeChatComparison(seed: .instructions(request.instructions), tools: tools)
  _ = try await freshTools.ask(general, label: "fresh / tools / app instructions")
  _ = try await retained.ask(general, label: "retained native tool history")
  let restored = try NativeChatComparison(seed: .transcript(transcript), tools: tools)
  _ = try await restored.ask(general, label: "restored exact native tool history")
  let rebuilt = try NativeChatComparison(seed: .transcript(canonical), tools: tools)
  _ = try await rebuilt.ask(general, label: "reconstructed canonical tool history")
  let nativeStream = try NativeChatComparison(seed: .transcript(transcript), tools: tools)
  _ = try await nativeStream.ask(
    general, label: "streamed / exact native history", delivery: .streamed)
  let canonicalStream = try NativeChatComparison(seed: .transcript(canonical), tools: tools)
  _ = try await canonicalStream.ask(
    general, label: "streamed / canonical history", delivery: .streamed)
  for (label, harness) in [
    ("retained", retained), ("restored", restored), ("reconstructed", rebuilt),
  ] {
    let reply = try await harness.ask(
      "What was the URL you found earlier?", label: "\(label) / follow-up")
    #expect(reply.text.contains(savedURL))
  }
  try await compareApplicationConversation(library: library, messages: messages)
  try await compareLiveApplicationContinuation(library: library, question: general)
}

private func comparisonRequest(_ messages: [ChatMessage], tools: [any ConversationTool])
  -> TextGenerationRequest
{
  ChatReplyGenerator.request(
    for: .init(
      companionName: "Pogo",
      profile: .init(personality: "Curious and upbeat"), messages: messages),
    tools: tools.map(\.definition))
}

private struct NativeChatComparison {
  enum Seed {
    case instructions(String)
    case transcript(Transcript)
  }
  enum Delivery { case complete, streamed }
  static let maximumResponseTokens = 240

  let session: LanguageModelSession
  let registered: [AppleConversationTool]
  private let invocation: AppleToolInvocation
  private let tools: [any ConversationTool]
  init(seed: Seed, tools: [any ConversationTool]) throws {
    let invocation = AppleToolInvocation()
    registered = try tools.map {
      try AppleConversationTool($0.definition, invoke: invocation.invoke)
    }
    switch seed {
    case .instructions(let instructions):
      session = LanguageModelSession(tools: registered, instructions: instructions)
    case .transcript(let transcript):
      session = LanguageModelSession(tools: registered, transcript: transcript)
    }
    self.invocation = invocation
    self.tools = tools
  }
  func ask(_ question: String, label: String, delivery: Delivery = .complete) async throws
    -> ChatReply
  {
    let toolbox = try ConversationToolbox(tools: tools, progress: { _ in })
    await invocation.open(toolbox)
    do {
      let tokens = try await inputTokenCount(question)
      let answer = try await generate(question, delivery: delivery)
      await invocation.close()
      let exchanges = await toolbox.exchanges
      print(
        "APPLE COMPARISON [\(label)] inputTokens=\(tokens); calls=\(exchanges.map { $0.call.name }); answer=\(answer)"
      )
      return await .init(text: answer, sources: toolbox.sources, exchanges: exchanges)
    } catch {
      await invocation.close()
      print("APPLE COMPARISON [\(label)] error=\(String(reflecting: error))")
      throw error
    }
  }

  private func inputTokenCount(_ question: String) async throws -> Int {
    guard #available(macOS 26.4, *) else {
      throw TextModelError.unavailable(
        "This comparison requires native token counting on macOS 26.4 or later.")
    }
    let entries =
      Array(session.transcript) + [
        Transcript.Entry.prompt(.init(segments: [.text(.init(content: question))]))
      ]
    return try await SystemLanguageModel.default.tokenCount(for: entries)
  }

  private func generate(_ question: String, delivery: Delivery) async throws -> String {
    let options = GenerationOptions(
      samplingMode: .greedy, maximumResponseTokens: Self.maximumResponseTokens)
    switch delivery {
    case .complete:
      return try await session.respond(to: question, options: options).content
    case .streamed:
      var answer = ""
      for try await snapshot in session.streamResponse(to: question, options: options) {
        answer = snapshot.content
      }
      return answer
    }
  }
}

private func compareApplicationConversation(library: VaultLibrary, messages: [ChatMessage])
  async throws
{
  let backend = AppleReasoningBackend()
  let tools: [any ConversationTool] = [
    VaultSearchTool(library: library), VaultReadTool(library: library),
  ]
  let probe = ComparisonBackend(apple: backend, expected: comparisonRequest(messages, tools: tools))
  let service = LocalConversationService(
    resolveBackend: { probe }, tools: tools, turns: .init())
  let context = ChatContext(
    companionName: "Pogo", profile: .init(personality: "Curious and upbeat"), messages: messages)
  let reply = try await service.reply(to: context) { event in
    if case .compacting = event { print("APPLE COMPARISON [application adapter] compacting") }
  }
  print(
    "APPLE COMPARISON [application adapter / same canonical history] calls=\(reply.exchanges.map { $0.call.name }); answer=\(reply.text)"
  )
  await backend.stop()
}

private struct ComparisonBackend: ConversationBackend {
  var reasoningTokenReserve: Int { apple.reasoningTokenReserve }
  let apple: AppleReasoningBackend
  let expected: TextGenerationRequest
  func availabilityNotice(localeIdentifier: String?) async -> String? {
    await apple.availabilityNotice(localeIdentifier: localeIdentifier)
  }
  func inputTokenCount(_ request: TextGenerationRequest) async throws -> Int {
    try await apple.inputTokenCount(request)
  }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> String {
    try await apple.generate(request, format: format)
  }
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) async throws -> String
  {
    try await streamConversation(request, tools: tools, receive: { _ in })
  }
  func streamConversation(
    _ request: TextGenerationRequest, tools: ConversationToolbox,
    receive: @escaping TextDeltaSink
  ) async throws -> String {
    #expect(request.instructions == expected.instructions)
    #expect(request.messages == expected.messages)
    #expect(request.tools == expected.tools)
    #expect(request.style == expected.style)
    #expect(request.maximumTokens == expected.maximumTokens)
    #expect(
      AppleGenerationOptions.make(request)
        == GenerationOptions(
          samplingMode: .greedy,
          maximumResponseTokens: NativeChatComparison.maximumResponseTokens))
    print(
      "APPLE COMPARISON [application request] instructions/messages/tools/style/token limit compared exactly"
    )
    return try await apple.streamConversation(request, tools: tools, receive: receive)
  }
}

private func compareLiveApplicationContinuation(library: VaultLibrary, question: String)
  async throws
{
  let creations = Mutex(0)
  let sessions = AppleConversationSessions { request, invocation in
    creations.withLock { $0 += 1 }
    print("APPLE COMPARISON [live session created] history messages=\(request.messages.count)")
    return try NativeAppleChatSession(request: request, invocation: invocation)
  }
  let backend = AppleReasoningBackend(conversations: sessions)
  let service = LocalConversationService(
    resolveBackend: { backend },
    tools: [VaultSearchTool(library: library), VaultReadTool(library: library)], turns: .init())
  let lifetime = TextModelLifetime()
  await service.retain(for: lifetime)
  let first = ChatMessage(role: .user, text: "Which URLs did I save?")
  func context(_ messages: [ChatMessage]) -> ChatContext {
    .init(
      companionName: "Pogo", profile: .init(personality: "Curious and upbeat"), messages: messages
    )
    .inTurn(UUID(), session: lifetime.id)
  }
  do {
    let initial = try await service.reply(to: context([first]))
    let reply = try await service.reply(
      to: context([
        first,
        .init(
          role: .companion, text: initial.text,
          evidence: .init(sources: initial.sources, exchanges: initial.exchanges)),
        .init(role: .user, text: question),
      ]))
    print(
      "APPLE COMPARISON [live retained application] creations=\(creations.withLock { $0 }); calls=\(reply.exchanges.map { $0.call.name }); answer=\(reply.text)"
    )
    #expect(creations.withLock { $0 } == 1)
    await lifetime.end()
  } catch {
    await lifetime.end()
    throw error
  }
}
