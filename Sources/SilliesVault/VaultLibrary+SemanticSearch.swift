import Foundation
import SilliesCore

extension VaultLibrary {
  package var isPreparingSearch: Bool { indexTask != nil || contentTask != nil }
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
    let failure = contentFailure ?? indexFailure
    guard let embeddings else { return (nil, failure) }
    return (try storage().vaultIndexProgress(provider: embeddings.identity), failure)
  }

  package func retrySearchPreparation() {
    resumeContentPreparation()
    indexFailure = nil
    scheduleIndex()
  }

  package func relatedMatches(_ request: VaultSearchRequest) async throws -> [VaultSearchMatch] {
    try await relatedSearch(request).matches
  }

  package func relatedSearch(_ request: VaultSearchRequest) async throws -> VaultRelatedSearchResult
  {
    guard !request.query.isEmpty, request.category != .links, let access = embeddings else {
      return .init(matches: [], availability: .unavailable)
    }
    _ = try storage()
    let generation = searchRevision
    do {
      let matches = try await SemanticSearchDeadline.perform(
        purpose: request.consumer == .workspace ? .workspace : .assistant
      ) { [semanticSearches, directory] in
        guard let vector = try await access.embed(.init(text: request.query, purpose: .query))
        else { throw SearchEmbeddingError.unavailable }
        let usesGlobalRanking =
          request.category == .all && request.workspaceQuery?.searchesAllActiveItems != false
        let candidates =
          usesGlobalRanking
          ? try await access.vectorIndex?.search(
            .init(directory: directory, embedding: vector, limit: 256)) : nil
        return try await semanticSearches.search(
          request, embedding: vector, provider: access.identity, candidates: candidates)
      }
      try Task.checkCancellation()
      guard generation == searchRevision else { return .init(matches: [], availability: .changed) }
      let progress = try storage().vaultIndexProgress(provider: access.identity)
      return .init(
        matches: matches, availability: progress.processed < progress.total ? .preparing : .ready)
    } catch is CancellationError {
      try Task.checkCancellation()
      return .init(matches: [], availability: .unavailable)
    } catch SemanticSearchDeadline.Failure.exceeded {
      return .init(matches: [], availability: .timedOut)
    } catch SearchEmbeddingError.timedOut {
      return .init(matches: [], availability: .timedOut)
    } catch SearchEmbeddingError.unavailable {
      return .init(matches: [], availability: .unavailable)
    } catch {
      fputs("Vault semantic search unavailable: \(error)\n", stderr)
      return .init(matches: [], availability: .failed(error.localizedDescription))
    }
  }

  func scheduleIndex() {
    guard indexTask == nil, let access = embeddings else { return }
    indexTask = Task { [weak self] in await self?.prepareIndex(access) }
  }

  private func prepareIndex(_ access: SearchEmbeddingAccess) async {
    defer { indexTask = nil }
    var completed = 0
    do {
      while true {
        try Task.checkCancellation()
        if let item = try storage().pendingVaultEmbedding(provider: access.identity) {
          let vector = try await access.embed(.init(text: item.text, purpose: .passage))
          try Task.checkCancellation()
          guard embeddings?.identity == access.identity else { return }
          try storage().saveVaultEmbedding(vector, for: item, provider: access.identity)
          completed += 1
          if completed.isMultiple(of: 32) {
            _ = try await access.vectorIndex?.advance(directory)
            try storage().pruneVectorChanges()
          }
        } else if let passage = try storage().pendingPassage() {
          try storage().savePassage(passage)
        } else if try await access.vectorIndex?.advance(directory) != true {
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
