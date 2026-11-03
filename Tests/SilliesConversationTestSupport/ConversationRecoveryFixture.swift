import Foundation
import SilliesCore
import SilliesPersistence

package struct ConversationRecoveryFixture: Codable, Sendable {
  package static let manifestName = "recovery-committed.json"
  package let user: ChatMessage
  package let reply: ChatMessage
  package let draft: String
  package let readingMessageID: UUID

  package static func load(at directory: URL) throws -> Self {
    try JSONDecoder().decode(
      Self.self, from: Data(contentsOf: directory.appendingPathComponent(manifestName)))
  }

  package static func commit(at directory: URL) throws -> Self {
    let fixture = try StoredConversationFixture.load(at: directory)
    let database = try ConversationDatabase(directory: directory)
    let state = Self(
      user: .init(role: .user, text: "Recovery question: recoverycommittedneedle"),
      reply: ChatMessage(role: .companion, text: "A delivered prefix and an unfinished reply.")
        .withDelivery(.streaming, spokenText: "A delivered prefix"),
      draft: "Keep this draft after a process restart.", readingMessageID: fixture.landmarks[0].id)
    try database.save(
      .init(
        handle: fixture.handle, messages: [state.user, state.reply],
        checkpoint: .init(
          draft: state.draft, language: "fr", readingMessageID: state.readingMessageID),
        savedAt: .now))
    try JSONEncoder().encode(state).write(
      to: directory.appendingPathComponent(manifestName), options: .atomic)
    return state
  }
}
