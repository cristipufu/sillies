import Foundation
import SilliesCore
import SilliesPersistence

/// Synthetic data shared by the storage subprocess and headless application checks.
package struct StoredConversationFixture: Codable, Sendable {
  package static let manifestName = "synthetic-conversation.json"
  package static let owner = ConversationOwner(id: "scale-pogo", name: "Pogo")
  package let messageCount: Int
  package let handle: ConversationHandle
  package let landmarks: [ChatMessage]
  package let memory: ConversationMemory

  package static func load(at directory: URL) throws -> Self {
    let fixture = try JSONDecoder().decode(
      Self.self, from: Data(contentsOf: directory.appendingPathComponent(manifestName)))
    guard fixture.handle.companionID == owner.id, (4...1_000_000).contains(fixture.messageCount),
      fixture.landmarks.count == 3
    else { throw ConversationStorageError.invalidData }
    return fixture
  }

  package static func seed(at directory: URL, count: Int) throws -> Self {
    guard (4...1_000_000).contains(count),
      !FileManager.default.fileExists(
        atPath: directory.appendingPathComponent(ConversationDatabase.filename).path)
    else { throw ConversationStorageError.invalidData }
    let database = try ConversationDatabase(directory: directory)
    let opened = try database.open(owner)
    let batchSize = 256
    let landmarkIndices: Set<Int> = [0, count / 2, count - 1]
    var landmarks: [ChatMessage] = []
    var checkpointID: UUID?
    for start in stride(from: 0, to: count, by: batchSize) {
      let messages = (start..<min(count, start + batchSize)).map { index in
        let message = message(at: index)
        if landmarkIndices.contains(index) { landmarks.append(message) }
        if index == 1 { checkpointID = message.id }
        return message
      }
      try database.save(
        .init(
          handle: opened.handle, messages: messages, checkpoint: .init(),
          savedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(start))))
    }
    let memory = ConversationMemory(
      summary: "The original calibration reference is quartz-37.",
      throughMessageID: checkpointID)
    guard
      try database.advanceCheckpoint(
        .init(
          handle: opened.handle, expected: database.checkpoint(opened.handle), replacement: memory))
    else { throw ConversationStorageError.changed }
    let fixture = Self(
      messageCount: count, handle: opened.handle, landmarks: landmarks, memory: memory)
    try JSONEncoder().encode(fixture).write(
      to: directory.appendingPathComponent(manifestName), options: .atomic)
    return fixture
  }

  private static func message(at index: Int) -> ChatMessage {
    var text =
      "Archive entry \(index), historyneedle\(index), project \(index % 100). We discussed the next steps and kept the notes locally. Café, résumé, ședință, 日本語."
    if index == 0 { text += " The original calibration reference is quartz-37." }
    if index.isMultiple(of: 97) {
      text += String(repeating: " Longer source material for the next discussion.", count: 30)
    }
    return .init(role: index.isMultiple(of: 2) ? .user : .companion, text: text)
  }
}
