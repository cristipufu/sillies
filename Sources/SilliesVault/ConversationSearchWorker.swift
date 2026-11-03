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

  private func storage() throws -> ConversationSearchDatabase {
    if let database { return database }
    let opened = try ConversationSearchDatabase(directory: directory)
    database = opened
    return opened
  }
}
