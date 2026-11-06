import Foundation
import SilliesCore

extension VaultLibrary {
  package func useSearchEmbeddings(_ access: SearchEmbeddingAccess?) async throws {
    let token = UUID()
    indexGeneration = token
    searchRevision = UUID()
    let previous = indexTask
    previous?.cancel()
    await previous?.value
    guard token == indexGeneration else { return }
    indexTask = nil
    embeddings = access
    indexFailure = nil
    if let access {
      try storage().removeVaultEmbeddings(except: access.identity)
      scheduleIndex()
    }
  }

  package func rebuildSearchIndex() throws {
    guard let embeddings else { return }
    try storage().resetVaultEmbeddings(provider: embeddings.identity)
    indexFailure = nil
    scheduleIndex()
  }

  package func searchIndexStatus() throws -> (SearchIndexProgress?, String?) {
    guard let embeddings else { return (nil, indexFailure) }
    return (try storage().vaultIndexProgress(provider: embeddings.identity), indexFailure)
  }

  package func relatedMatches(_ request: VaultSearchRequest) async throws -> [VaultSearchMatch] {
    guard !request.query.isEmpty, request.category != .links, let access = embeddings else {
      return []
    }
    _ = try storage()
    let generation = searchRevision
    do {
      let matches = try await SemanticSearchDeadline.perform { [semanticSearches] in
        guard let vector = try await access.embed(.init(text: request.query, purpose: .query))
        else { return [VaultSearchMatch]() }
        return try await semanticSearches.search(
          request, embedding: vector, provider: access.identity)
      }
      try Task.checkCancellation()
      guard generation == searchRevision else { return [] }
      return matches
    } catch is CancellationError {
      try Task.checkCancellation()
      return []
    } catch SearchEmbeddingError.unavailable { return [] } catch {
      fputs("Vault semantic search unavailable: \(error)\n", stderr)
      return []
    }
  }

  func scheduleIndex() {
    guard indexTask == nil, let access = embeddings else { return }
    indexTask = Task { [weak self] in await self?.prepareIndex(access) }
  }

  private func prepareIndex(_ access: SearchEmbeddingAccess) async {
    defer { indexTask = nil }
    do {
      while true {
        try Task.checkCancellation()
        if let item = try storage().pendingVaultEmbedding(provider: access.identity) {
          let vector = try await access.embed(.init(text: item.text, purpose: .passage))
          try Task.checkCancellation()
          guard embeddings?.identity == access.identity else { return }
          try storage().saveVaultEmbedding(vector, for: item, provider: access.identity)
        } else if let passage = try storage().pendingPassage() {
          try storage().savePassage(passage)
        } else {
          return
        }
        await Task.yield()
      }
    } catch is CancellationError { return } catch {
      indexFailure = error.localizedDescription
      fputs("Vault index preparation failed: \(error)\n", stderr)
    }
  }
}
