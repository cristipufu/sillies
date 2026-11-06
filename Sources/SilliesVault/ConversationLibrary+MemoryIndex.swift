import Foundation
import SilliesCore

extension ConversationLibrary {
  package func useSearchEmbeddings(_ access: SearchEmbeddingAccess?) async throws {
    let generation = UUID()
    memoryIndexGeneration = generation
    let previous = memoryIndexTask
    previous?.cancel()
    await previous?.value
    guard generation == memoryIndexGeneration else { return }
    memoryIndexTask = nil
    memoryEmbeddings = access
    memorySearchGeneration = UUID()
    memoryIndexFailure = nil
    if let access {
      try storage().removeSearchEmbeddings(except: access.identity)
      scheduleMemoryIndex()
    }
  }

  package func rebuildMemoryIndex() throws {
    guard let access = memoryEmbeddings else { return }
    try storage().resetSearchEmbeddings(provider: access.identity)
    memoryIndexFailure = nil
    scheduleMemoryIndex()
  }

  package func memoryIndexStatus() throws -> (SearchIndexProgress?, String?) {
    guard let access = memoryEmbeddings else { return (nil, memoryIndexFailure) }
    return (try storage().memoryIndexProgress(provider: access.identity), memoryIndexFailure)
  }

  func scheduleMemoryIndex() {
    guard memoryIndexTask == nil, let access = memoryEmbeddings else { return }
    memoryIndexTask = Task { [weak self] in await self?.prepareMemoryIndex(access) }
  }

  private func prepareMemoryIndex(_ access: SearchEmbeddingAccess) async {
    defer { memoryIndexTask = nil }
    do {
      while true {
        try Task.checkCancellation()
        let batch = try storage().pendingSearchEmbeddings(provider: access.identity)
        guard !batch.isEmpty else { return }
        for item in batch {
          let vector = try await access.embed(.init(text: item.text, purpose: .passage))
          try Task.checkCancellation()
          guard memoryEmbeddings?.identity == access.identity else { return }
          try storage().saveSearchEmbedding(vector, for: item, provider: access.identity)
          await Task.yield()
        }
      }
    } catch is CancellationError { return } catch {
      memoryIndexFailure = error.localizedDescription
      fputs("Memory index preparation failed: \(error)\n", stderr)
    }
  }
}
