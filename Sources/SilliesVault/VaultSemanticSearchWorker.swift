import Foundation
import SilliesCore
import SilliesPersistence

actor VaultSemanticSearchWorker {
  private let directory: URL
  private var database: VaultSemanticSearchDatabase?
  init(directory: URL) { self.directory = directory }

  func search(_ request: VaultSearchRequest, embedding: SearchEmbedding, provider: String) throws
    -> [VaultSearchMatch]
  {
    dispatchPrecondition(condition: .notOnQueue(.main))
    return try storage().search(request, embedding: embedding, provider: provider)
  }

  private func storage() throws -> VaultSemanticSearchDatabase {
    if let database { return database }
    let opened = try VaultSemanticSearchDatabase(directory: directory)
    database = opened
    return opened
  }
}
