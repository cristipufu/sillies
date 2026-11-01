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
  let rejected = try await toolbox.invoke(
    .init(
      id: "invalid", name: "save_memory",
      arguments: Data(#"{"key":"birthday","value":"June 2","quote":"My birthday is June 2."}"#.utf8)
    ))
  #expect(rejected.contains("Not saved"))
  #expect(try await library.memories(opened.handle, query: "").isEmpty)
  let call = ConversationToolCall(
    id: "remember", name: "save_memory",
    arguments: Data(
      #"{"key":"reply_style","value":"Short answers","quote":"I prefer short answers."}"#.utf8))
  _ = try await toolbox.invoke(call)
  try await toolbox.beginRecovery()
  _ = try await toolbox.invoke(call)
  #expect(try await library.recentMemoryChanges(opened.handle).count == 1)
  let bolt = try await library.open(.init(id: "bolt", name: "Bolt"))
  #expect(try await library.memories(bolt.handle, query: "").isEmpty)
  let found = try await toolbox.invoke(
    .init(id: "search", name: "search_conversation", arguments: Data(#"{"query":"birthday"}"#.utf8))
  )
  #expect(found.contains("June 2"))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_CHAT_TOOL_CHECK"] == "1"))
func appleConversationFiveToolQualityCheck() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let library = ConversationLibrary(directory: directory)
  let vault = VaultLibrary(directory: directory)
  let opened = try await library.open(.init(id: "pogo", name: "Pogo"))
  let backend = AppleReasoningBackend()
  try #require(await backend.availabilityNotice(localeIdentifier: "en") == nil)
  let service = LocalConversationService(
    resolveBackend: { backend },
    tools: [VaultSearchTool(library: vault), VaultReadTool(library: vault)], turns: .init(),
    historyTools: { context in
      ConversationHistoryTools(conversations: library, memories: library).tools(for: context)
    })
  let lifetime = TextModelLifetime()
  await service.retain(for: lifetime)
  defer { Task { await lifetime.end() } }
  var messages: [ChatMessage] = []
  var memory = ConversationMemory()
  for question in [
    "My birthday is May 14.", "What is the tallest mountain in the world?", "When is my birthday?",
  ] {
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
          companionName: "Pogo",
          profile: .init(personality: "Warm and curious", languageIdentifier: "en"),
          messages: messages, memory: memory
        ).inTurn(UUID(), session: lifetime.id).inHistory(opened.handle), progress: { _ in })
      print(
        "FIVE-TOOL QUALITY | \(question) | \(started.duration(to: .now)) | tools=\(reply.exchanges.map { $0.call.name }) | \(reply.text)"
      )
      memory = reply.memory
      messages.append(
        .init(
          role: .companion, text: reply.text,
          evidence: .init(sources: reply.sources, exchanges: reply.exchanges)))
    } catch {
      print("FIVE-TOOL QUALITY | \(question) | error=\(error)")
      throw error
    }
  }
  print("FIVE-TOOL MEMORIES | \(try await library.memories(opened.handle, query: "").map(\.value))")
}
