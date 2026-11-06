import Foundation
import SilliesCore
import Testing

@testable import SilliesPersistence

@Test func conversationDateIndexUpgradePreservesVersionFourMessagesAndDrafts() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let original = try ConversationDatabase(directory: directory)
  let snapshot = try original.open(.init(id: "pogo", name: "Pogo"))
  let message = ChatMessage(role: .user, text: "Preserve this thought.")
  let date = Date(timeIntervalSince1970: 1_780_000_000)
  try original.save(
    .init(
      handle: snapshot.handle, messages: [message], checkpoint: .init(draft: "Unsent"),
      savedAt: date))
  try original.sql.execute("DROP INDEX conversation_messages_date")
  try original.sql.execute("DROP TABLE personal_facts")
  try original.sql.execute("DROP TABLE personal_fact_state")
  try original.sql.execute("PRAGMA user_version=4")
  let updated = try ConversationDatabase(directory: directory)
  let reopened = try updated.open(.init(id: "pogo", name: "Pogo"))
  #expect(reopened.handle == snapshot.handle && reopened.checkpoint.draft == "Unsent")
  let found = try updated.page(.init(handle: snapshot.handle, position: .onOrAfter(date)))
  #expect(found.entries.map(\.id) == [message.id])
  #expect(try updated.sql.integer("PRAGMA user_version") == ConversationDatabase.schemaVersion)
}
