import Foundation
import SilliesCore
import Testing

@testable import SilliesReasoning
@testable import SilliesVault

@Test func archiveRecallFindsEvidenceBeyondTheMessageOpening() async throws {
  let fixture = ArchiveRecallFixture()
  defer { fixture.remove() }
  let library = ConversationLibrary(directory: fixture.directory)
  let opened = try await library.open(.init(id: "pogo", name: "Pogo"))
  let statement = "Ștefan chose the mural pigment: ultramarine."
  let message = ChatMessage(
    role: .user,
    text: String(repeating: "Preparations are complete. ", count: 160) + statement
      + String(repeating: "The room is ready. ", count: 50))
  try await fixture.save([message], in: opened.handle, library: library)
  let matches = try await library.search(.init(companionID: "pogo", query: "Stefan mural pigment"))
  let match = try #require(matches.first)
  #expect(match.entry.message.text == message.text)
  #expect(match.excerpt.contains(statement))
  #expect(match.excerpt.count < message.text.count)
  let tool = fixture.tool(library: library, handle: opened.handle)
  let output = try await tool.call(arguments: Data(#"{"query":"Stefan mural pigment"}"#.utf8))
  let result = try ArchiveRecallFixture.decode(output.text)
  #expect(result.source == "conversation")
  #expect(result.status == "matches")
  #expect(result.messages.first?.excerpt.contains(statement) == true)
  #expect(result.messages.first?.isCompleteMessage == false)
  #expect(result.messages.first?.speaker == "user")
  #expect(result.messages.first?.date == fixture.date)
}

@Test func archiveRecallPreservesChronologyAndCompleteEvidenceUnderSmallerBudgets() async throws {
  let fixture = ArchiveRecallFixture()
  defer { fixture.remove() }
  let library = ConversationLibrary(directory: fixture.directory)
  let opened = try await library.open(.init(id: "pogo", name: "Pogo"))
  let messages = (0..<6).map { ChatMessage(role: .user, text: "Workshop label: \($0).") }
  try await fixture.save(messages, in: opened.handle, library: library)
  let output = try await fixture.tool(library: library, handle: opened.handle).call(
    arguments: Data(#"{"query":"workshop label"}"#.utf8))
  #expect(output.representations.count == 3)
  for (text, count) in zip(output.representations, [4, 2, 1]) {
    let result = try ArchiveRecallFixture.decode(text)
    #expect(result.hasMoreMatches)
    #expect(result.messages.count == count)
    #expect(result.messages.map(\.sequence) == result.messages.map(\.sequence).sorted())
    #expect(result.messages.last?.messageID == messages.last?.id)
    #expect(result.messages.allSatisfy { $0.isCompleteMessage })
  }
}

@Test func archiveRecallDistinguishesAnEmptyQueryFromMissingEvidenceAndScopesSources() async throws
{
  let fixture = ArchiveRecallFixture()
  defer { fixture.remove() }
  let library = ConversationLibrary(directory: fixture.directory)
  let pogo = try await library.open(.init(id: "pogo", name: "Pogo"))
  let bolt = try await library.open(.init(id: "bolt", name: "Bolt"))
  let current = ChatMessage(role: .user, text: "Who brings the telescope?")
  try await fixture.save([current], in: pogo.handle, library: library)
  try await fixture.save(
    [.init(role: .user, text: "Luca brings the telescope.")], in: bolt.handle, library: library)
  let tool = ConversationSearchTool(
    repository: library, handle: pogo.handle, currentMessageID: current.id)
  let miss = try await tool.call(arguments: Data(#"{"query":"telescope"}"#.utf8))
  let missing = try ArchiveRecallFixture.decode(miss.text)
  #expect(missing.status == "noMatches")
  #expect(missing.messages.isEmpty)
  #expect(!missing.hasMoreMatches)
  let empty = try await tool.call(arguments: Data(#"{"query":"  "}"#.utf8))
  #expect(try ArchiveRecallFixture.decode(empty.text).status == "queryRequired")
}

@Test func archiveRecallKeepsAssistantClaimsAttributedAndCannotReviveDeletedMessages() async throws
{
  let fixture = ArchiveRecallFixture()
  defer { fixture.remove() }
  let library = ConversationLibrary(directory: fixture.directory)
  let opened = try await library.open(.init(id: "pogo", name: "Pogo"))
  let original = ChatMessage(role: .user, text: "Orchard visit: Tuesday.")
  let companion = ChatMessage(role: .companion, text: "Orchard visit: Wednesday.")
  try await fixture.save([original, companion], in: opened.handle, library: library)
  let tool = fixture.tool(library: library, handle: opened.handle)
  let before = try await tool.call(arguments: Data(#"{"query":"orchard"}"#.utf8))
  let result = try ArchiveRecallFixture.decode(before.text)
  #expect(result.messages.map(\.speaker) == ["user", "companion"])
  #expect(result.messages.map(\.excerpt) == [original.text, companion.text])
  try await library.save(
    .init(
      handle: opened.handle, messages: [original.withText("Orchard visit: Thursday.")],
      checkpoint: .init(), removedMessageIDs: [companion.id], savedAt: fixture.date))
  let after = try await tool.call(arguments: Data(#"{"query":"orchard"}"#.utf8))
  #expect(
    try ArchiveRecallFixture.decode(after.text).messages.map(\.excerpt) == [
      "Orchard visit: Thursday."
    ])
}

@Test func archiveRecallReportsOversizedEvidenceWithoutClippingOrMisreportingAMiss() async throws {
  let fixture = ArchiveRecallFixture()
  defer { fixture.remove() }
  let library = ConversationLibrary(directory: fixture.directory)
  let opened = try await library.open(.init(id: "pogo", name: "Pogo"))
  let message = ChatMessage(
    role: .user, text: String(repeating: "x", count: 12_000) + " orchard notes")
  try await fixture.save([message], in: opened.handle, library: library)
  let output = try await fixture.tool(library: library, handle: opened.handle).call(
    arguments: Data(#"{"query":"orchard"}"#.utf8))
  for text in output.representations {
    let result = try ArchiveRecallFixture.decode(text)
    #expect(text.utf8.count < 1_024)
    #expect(result.status == "matches")
    #expect(result.messages.first?.messageID == message.id)
    #expect(result.messages.first?.excerpt.isEmpty == true)
    #expect(result.messages.first?.omissionReason != nil)
    #expect(result.messages.first?.isCompleteMessage == false)
  }
}

private struct ArchiveRecallFixture {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let date = Date(timeIntervalSince1970: 1_793_534_400)

  struct Evidence: Decodable {
    struct Message: Decodable {
      let messageID: UUID
      let sequence: Int64
      let date: Date
      let speaker: String
      let excerpt: String
      let isCompleteMessage: Bool
      let omissionReason: String?
    }
    let source: String
    let status: String
    let hasMoreMatches: Bool
    let messages: [Message]
  }

  static func decode(_ text: String) throws -> Evidence {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(Evidence.self, from: Data(text.utf8))
  }

  func save(_ messages: [ChatMessage], in handle: ConversationHandle, library: ConversationLibrary)
    async throws
  {
    try await library.save(
      .init(handle: handle, messages: messages, checkpoint: .init(), savedAt: date))
  }

  func tool(library: ConversationLibrary, handle: ConversationHandle) -> ConversationSearchTool {
    .init(repository: library, handle: handle, currentMessageID: UUID())
  }

  func remove() {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
}
