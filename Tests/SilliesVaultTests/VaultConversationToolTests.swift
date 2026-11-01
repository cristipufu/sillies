import Foundation
import SilliesCore
import SilliesPersistence
import SilliesReasoning
import SilliesTextModels
import Testing

@testable import SilliesVault

private func savedItem(_ kind: CompanionSkillKind, app: String, text: String) -> SessionRecord {
  SessionRecord(
    kind: kind,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: app)),
    content: .init(text: .init(transcript: text)))
}
private func removeVaultFixture(_ directory: URL) {
  do { try FileManager.default.removeItem(at: directory) } catch {
    Issue.record("Fixture cleanup: \(error)")
  }
}

@Test func vaultToolsFindScreenshotsSavedURLsAndLateMeetingTopics() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeVaultFixture(directory) }
  let library = VaultLibrary(directory: directory)
  var screenshot = savedItem(.snap, app: "Ghostty", text: "")
  screenshot.imageFilename = "ghostty.png"
  screenshot.extractedText = "Build succeeded"
  var stash = savedItem(.stash, app: "Safari", text: "")
  stash.stashedItems = ["https://example.com/roadmap", "https://example.com/design"]
  let meeting = savedItem(
    .listen, app: "Planning",
    text: String(repeating: "Earlier discussion. ", count: 2_000)
      + "We discussed the aurora rollout and assigned the migration to Alex.")
  let unrelated = (0..<40).map { savedItem(.snap, app: "Browser", text: "Other capture \($0)") }
  _ = try await library.commit(
    .init(records: ([screenshot, stash, meeting] + unrelated).map(VaultRecordWrite.insert)))
  let before = try await library.metrics().loadedBodies
  let screenshotMatches = try await library.search(
    .init(query: "ghostty terminal", category: .screenshots))
  #expect(screenshotMatches.map(\.header.id) == [screenshot.id])
  let meetingMatches = try await library.search(.init(query: "aurora", category: .meetings))
  #expect(meetingMatches.map(\.header.id) == [meeting.id])
  #expect(meetingMatches.first?.excerpt.contains("aurora") == true)
  #expect(try await library.metrics().loadedBodies == before)
  #expect(
    try await library.search(.init(query: "", limit: 100)).count
      == VaultSearchRequest.maximumResults)
  #expect(try await library.search(.init(query: "\" OR * --")).isEmpty)
  let search = VaultSearchTool(library: library)
  let links = try await search.call(arguments: Data(#"{"query":"","category":"links"}"#.utf8))
  #expect(links.sources.map(\.id) == [stash.id])
  #expect(links.sources.first?.links.map(\.absoluteString) == stash.stashedItems)
  let read = VaultReadTool(library: library)
  let args = try JSONEncoder().encode(["recordID": meeting.id.uuidString, "query": "aurora"])
  let detail = try await read.call(arguments: args)
  #expect(detail.sources.first?.excerpt.contains("assigned the migration to Alex") == true)
  #expect((detail.sources.first?.excerpt.count ?? 0) <= VaultToolContent.maximumExcerptCharacters)
  _ = try await library.commit(.init(deletion: .records([meeting.id])))
  #expect(try await read.call(arguments: args).sources.isEmpty)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_CHAT_MODEL_CHECK"] == "1"))
func appleChatUsesNativeVaultToolsForTheRequestedRecordTypes() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeVaultFixture(directory) }
  let library = VaultLibrary(directory: directory)
  var screenshot = savedItem(.snap, app: "Ghostty", text: "")
  screenshot.imageFilename = "ghostty.png"
  var links = savedItem(.stash, app: "Safari", text: "")
  links.stashedItems = ["https://example.com/project-aurora"]
  let meeting = savedItem(
    .listen, app: "Aurora planning",
    text: "We discussed the aurora rollout. Alex owns the migration, with a deadline of Friday.")
  _ = try await library.commit(
    .init(records: [screenshot, links, meeting].map(VaultRecordWrite.insert)))
  let service = LocalConversationService(
    resolveBackend: { LoggedAppleBackend() },
    tools: [VaultSearchTool(library: library), VaultReadTool(library: library)], turns: .init())
  try #require(await service.availabilityNotice(localeIdentifier: "en") == nil)
  for (question, expected) in [
    ("Show me the screenshot with the Ghostty terminal", screenshot.id),
    ("Which URLs did I save?", links.id),
    ("Which meeting did I talk about aurora?", meeting.id),
  ] {
    let reply = try await service.reply(
      to: .init(
        companionName: "Pogo", profile: .init(personality: "Curious and upbeat"),
        messages: [.init(role: .user, text: question)]))
    print(
      "VAULT MODEL CHECK: \(question) → \(reply.text); tools: \(reply.exchanges.map { $0.call.name + String(decoding: $0.call.arguments, as: UTF8.self) })"
    )
    #expect(reply.sources.contains { $0.id == expected })
    #expect(reply.exchanges.contains { $0.call.name == "search_vault" })
  }
}

private struct LoggedAppleBackend: ConversationBackend {
  private let apple = AppleReasoningBackend()
  var contextWindowTokens: Int { apple.contextWindowTokens }
  func inputTokenCount(_ request: TextGenerationRequest) async throws -> Int {
    do { return try await apple.inputTokenCount(request) } catch {
      print("NATIVE TOKEN COUNT FAILURE: \(String(reflecting: error))")
      throw error
    }
  }
  func availabilityNotice(localeIdentifier: String?) async -> String? {
    await apple.availabilityNotice(localeIdentifier: localeIdentifier)
  }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> String {
    try await apple.generate(request, format: format)
  }
  func converse(_ request: TextGenerationRequest, tools: ConversationToolbox) async throws -> String
  {
    try await streamConversation(request, tools: tools, receive: { _ in })
  }
  func streamConversation(
    _ request: TextGenerationRequest, tools: ConversationToolbox, receive: @escaping TextDeltaSink
  ) async throws -> String {
    do {
      let output = try await apple.streamConversation(request, tools: tools, receive: receive)
      print("RAW FIXTURE RESPONSE: \(output)")
      return output
    } catch {
      print("NATIVE CONVERSATION FAILURE: \(String(reflecting: error))")
      throw error
    }
  }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_CHAT_MODEL_CHECK"] == "1"))
func appleChatAnswersBoltsFirstSpokenGreeting() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { removeVaultFixture(directory) }
  let library = VaultLibrary(directory: directory)
  let service = LocalConversationService(
    resolveBackend: { LoggedAppleBackend() },
    tools: [VaultSearchTool(library: library), VaultReadTool(library: library)], turns: .init())
  for attempt in 0..<3 {
    print("BOLT GREETING ATTEMPT: \(attempt)")
    let reply = try await service.reply(
      to: .init(
        companionName: "Bolt",
        profile: .init(
          personality: "Precise, practical and friendly. Dry robot humor in small doses."),
        messages: [.init(role: .user, text: "Hey man, what's uh what's your name?")]))
    #expect(!reply.text.isEmpty)
    #expect(reply.text.localizedCaseInsensitiveContains("Bolt"))
  }
}
