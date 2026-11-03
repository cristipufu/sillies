import Foundation
import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning
@testable import SilliesVault

@Test func conversationToolsScopeWritesToCurrentUserAndRecoveryDoesNotRepeatThem() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let library = ConversationLibrary(directory: directory)
  let opened = try await library.open(.init(id: "pogo", name: "Pogo"))
  let older = ChatMessage(role: .user, text: "My birthday is June 2.")
  let current = ChatMessage(role: .user, text: "I prefer short answers.")
  try await library.save(
    .init(handle: opened.handle, messages: [older, current], checkpoint: .init(), savedAt: Date()))
  let context = ChatContext(
    companionName: "Pogo", profile: .init(personality: "Friendly"), messages: [older, current]
  ).inHistory(opened.handle)
  let factory = ConversationHistoryTools(conversations: library, memories: library)
  let toolbox = try ConversationToolbox(tools: factory.tools(for: context), progress: { _ in })
  let call = ConversationToolCall(
    id: "remember", name: "save_memory",
    arguments: Data(
      #"{"key":"reply_style","value":"Short answers"}"#.utf8))
  _ = try await toolbox.invoke(call)
  try await toolbox.beginRecovery()
  _ = try await toolbox.invoke(call)
  #expect(try await library.recentMemoryChanges(opened.handle).count == 1)
  let saved = try #require(try await library.memories(opened.handle, query: "").first)
  #expect(saved.sourceMessageID == current.id)
  #expect(saved.sourceQuote == current.text)
  let bolt = try await library.open(.init(id: "bolt", name: "Bolt"))
  #expect(try await library.memories(bolt.handle, query: "").isEmpty)
  let found = try await toolbox.invoke(
    .init(id: "search", name: "search_conversation", arguments: Data(#"{"query":"birthday"}"#.utf8))
  )
  #expect(found.contains("June 2"))
  let currentSearch = try await toolbox.invoke(
    .init(
      id: "current", name: "search_conversation",
      arguments: Data(#"{"query":"short answers"}"#.utf8)))
  #expect(!currentSearch.contains(current.text))
}

@Test func memoryToolsBindOriginalUserEvidenceWithoutModelTranscription() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let library = ConversationLibrary(directory: directory)
  let opened = try await library.open(.init(id: "pogo", name: "Pogo"))
  let statement = ChatMessage(role: .user, text: "i'm Alex")
  try await library.save(
    .init(handle: opened.handle, messages: [statement], checkpoint: .init(), savedAt: Date()))
  let context = ChatContext(
    companionName: "Pogo", profile: .init(personality: "Friendly"), messages: [statement]
  ).inHistory(opened.handle)
  let tools = ConversationHistoryTools(conversations: library, memories: library).tools(
    for: context)
  let save = try #require(tools.first { $0.definition.name == "save_memory" })
  #expect(
    save.definition.parameters.filter { $0.requirement == .required }.map(\.name) == [
      "key", "value",
    ])
  _ = try await save.call(arguments: Data(#"{"key":"name","value":"Alex"}"#.utf8))
  let fact = try #require(try await library.memories(opened.handle, query: "name").first)
  #expect(fact.sourceQuote == "i'm Alex")
  #expect(fact.sourceMessageID == statement.id)
  let search = try #require(tools.first { $0.definition.name == "search_memories" })
  struct MemoryResult: Decodable {
    struct Fact: Decodable {
      let memoryID: UUID
      let revision: UUID
      let key: String
      let value: String
      let userStatement: String
    }
    let subject: String
    let facts: [Fact]
  }
  let output = try await search.call(arguments: Data(#"{"query":"name"}"#.utf8))
  let result = try JSONDecoder().decode(MemoryResult.self, from: Data(output.text.utf8))
  #expect(result.subject == "user")
  #expect(result.facts.first?.memoryID == fact.id)
  #expect(result.facts.first?.revision == fact.revision)
  #expect(result.facts.first?.key == "name")
  #expect(result.facts.first?.value == "Alex")
  #expect(result.facts.first?.userStatement == statement.text)
  let assistantContext = ChatContext(
    companionName: "Pogo", profile: context.profile,
    messages: [ChatMessage(role: .companion, text: "My name is Alex.")]
  ).inHistory(opened.handle)
  #expect(
    ConversationHistoryTools(conversations: library, memories: library).tools(for: assistantContext)
      .isEmpty)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_CHAT_TOOL_CHECK"] == "1"))
func appleConversationFiveToolQualityCheck() async throws {
  _ = try await appleConversationCheck(questions: [
    "My birthday is May 14.", "What is the tallest mountain in the world?", "When is my birthday?",
  ])
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_CHAT_TOOL_CHECK"] == "1"))
func appleChatSavesAndRecallsAnOriginalUserStatement() async throws {
  let result = try await appleConversationCheck(questions: [
    "do you know my name?", "i'm Alex", "so what's my name",
  ])
  #expect(
    result.memories.contains {
      $0.value.localizedCaseInsensitiveContains("Alex") && $0.sourceQuote == "i'm Alex"
    })
  #expect(result.replies.last?.text.localizedCaseInsensitiveContains("Alex") == true)
}

@Test(
  .enabled(if: ProcessInfo.processInfo.environment["SILLIES_CHAT_TOOL_CHECK"] == "1"),
  arguments: [ConversationOwner(id: "pogo", name: "Pogo"), .init(id: "bolt", name: "Bolt")])
func appleChatKeepsItsIdentitySeparateFromUserMemories(_ owner: ConversationOwner) async throws {
  let result = try await appleConversationCheck(
    questions: [
      "my name is Alex", "what's my name?", "what's your name?",
    ], owner: owner)
  let answer = try #require(result.replies.last?.text)
  #expect(answer.localizedCaseInsensitiveContains(owner.name))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_CHAT_TOOL_CHECK"] == "1"))
func appleChatKeepsItsIdentityAfterRetrievingUserMemories() async throws {
  let result = try await appleConversationCheck(questions: [
    "do you know my name?", "i'm Alex", "what's my name?", "what's your name?",
  ])
  #expect(result.memories.contains { $0.value == "Alex" })
  #expect(result.replies.contains { $0.exchanges.contains { $0.call.name == "search_memories" } })
  let answer = try #require(result.replies.last?.text)
  #expect(answer.localizedCaseInsensitiveContains("Pogo"))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_CHAT_TOOL_CHECK"] == "1"))
func appleChatCorrectsAnEarlierMistakenIdentityUsingItsProfile() async throws {
  let result = try await appleConversationCheck(
    questions: ["what's your name?"],
    history: [
      .init(role: .user, text: "my name is Alex"),
      .init(role: .companion, text: "Your name is Alex."),
      .init(role: .user, text: "what's your name?"),
      .init(role: .companion, text: "I'm Alex, your friendly window companion."),
    ])
  let answer = try #require(result.replies.last?.text)
  #expect(answer.localizedCaseInsensitiveContains("Pogo"))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_CHAT_TOOL_CHECK"] == "1"))
func appleChatRechecksPreviouslyMisattributedMemoryResults() async throws {
  let oldSearch = ConversationToolExchange(
    call: .init(
      id: "previous-name-search", name: "search_memories",
      arguments: Data(#"{"query":"name"}"#.utf8)),
    result: #"[{"key":"name","value":"Alex","quote":"my name is Alex"}]"#)
  let result = try await appleConversationCheck(
    questions: ["what's your name?"],
    history: [
      .init(role: .user, text: "my name is Alex"),
      .init(role: .companion, text: "Your name is Alex."),
      .init(role: .user, text: "what's your name?"),
      .init(
        role: .companion, text: "I'm Alex, your friendly window companion.",
        evidence: .init(exchanges: [oldSearch])),
    ], rememberedFact: .init(key: "name", value: "Alex"))
  let answer = try #require(result.replies.last?.text)
  #expect(answer.localizedCaseInsensitiveContains("Pogo"))
}

private struct AppleConversationCheckResult {
  let memories: [CompanionMemory]
  let replies: [ChatReply]
}

private func appleConversationCheck(
  questions: [String], owner: ConversationOwner = .init(id: "pogo", name: "Pogo"),
  history: [ChatMessage] = [], rememberedFact: MemoryFact? = nil
) async throws
  -> AppleConversationCheckResult
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let library = ConversationLibrary(directory: directory)
  let vault = VaultLibrary(directory: directory)
  let opened = try await library.open(owner)
  try await library.save(
    .init(handle: opened.handle, messages: history, checkpoint: .init(), savedAt: Date()))
  if let rememberedFact {
    let statement = try #require(history.first { $0.role == .user })
    _ = try await library.remember(
      .init(
        handle: opened.handle, fact: rememberedFact,
        source: .init(messageID: statement.id, quote: statement.text), savedAt: Date()))
  }
  let backend = AppleReasoningBackend()
  try #require(await backend.availabilityNotice(localeIdentifier: "en") == nil)
  let service = LocalConversationService(
    resolveBackend: { backend },
    tools: [VaultSearchTool(library: vault), VaultReadTool(library: vault)], turns: .init(),
    history: .init(
      repository: library,
      tools: { context in
        ConversationHistoryTools(conversations: library, memories: library).tools(for: context)
      }))
  let lifetime = TextModelLifetime()
  await service.retain(for: lifetime)
  defer { Task { await lifetime.end() } }
  var messages = history
  var memory = ConversationMemory()
  var replies: [ChatReply] = []
  for question in questions {
    let message = ChatMessage(role: .user, text: question)
    messages.append(message)
    try await library.save(
      .init(
        handle: opened.handle, messages: [message], checkpoint: .init(memory: memory),
        savedAt: Date()))
    let started = ContinuousClock.now
    do {
      let reply = try await service.reply(
        to: ChatContext(
          companionName: owner.name,
          profile: .init(personality: "Warm and curious", languageIdentifier: "en"),
          messages: messages, memory: memory
        ).inTurn(UUID(), session: lifetime.id).inHistory(opened.handle), progress: { _ in })
      print(
        "FIVE-TOOL QUALITY | \(question) | \(started.duration(to: .now)) | tools=\(reply.exchanges.map { $0.call.name }) | \(reply.text)"
      )
      memory = reply.memory
      replies.append(reply)
      messages.append(
        .init(
          role: .companion, text: reply.text,
          evidence: .init(sources: reply.sources, exchanges: reply.exchanges)))
    } catch {
      print("FIVE-TOOL QUALITY | \(question) | error=\(error)")
      throw error
    }
  }
  let memories = try await library.memories(opened.handle, query: "")
  print("FIVE-TOOL MEMORIES | \(memories.map(\.value))")
  return .init(memories: memories, replies: replies)
}
