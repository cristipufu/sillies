import Foundation
import SilliesCore
import SilliesPersistence

/// One serialized reader, independent of foreground page reads, saves and checkpoints.
actor ConversationSearchWorker {
  private let directory: URL
  private var database: ConversationSearchDatabase?

  init(directory: URL) { self.directory = directory }

  func search(_ request: ConversationSearchRequest) throws -> [ConversationSearchMatch] {
    try Task.checkCancellation()
    return try storage().search(request)
  }

  func memories(_ query: CompanionMemoryQuery) throws -> [CompanionMemory] {
    try Task.checkCancellation()
    return try storage().memories(query)
  }

  func semanticMemories(_ query: CompanionMemoryQuery, embedding: MemoryEmbedding, provider: String)
    throws -> [CompanionMemory]
  {
    try storage().semanticMemories(query, embedding: embedding, provider: provider)
  }

  private func storage() throws -> ConversationSearchDatabase {
    if let database { return database }
    let opened = try ConversationSearchDatabase(directory: directory)
    database = opened
    return opened
  }
}
