import Foundation
import SilliesCore

extension VaultLibrary {
  private static var cleanupYield: Duration { .milliseconds(20) }

  package func resumeCleanup() {
    cleanupEnabled = true
    scheduleCleanup()
  }

  package func stopCleanup() {
    cleanupEnabled = false
    cleanupGeneration = UUID()
    cleanupTask?.cancel()
    cleanupTask = nil
  }

  func scheduleCleanup() {
    guard cleanupEnabled, cleanupTask == nil else { return }
    let generation = UUID()
    cleanupGeneration = generation
    cleanupFailure = nil
    cleanupTask = Task { [weak self] in await self?.clean(generation: generation) }
  }

  package func cleanupStatus() throws -> (VaultCleanupProgress, String?) {
    (try storage().cleanupProgress(), cleanupFailure)
  }

  package func emptyTrash() throws {
    try storage().enqueueTrashCleanup(at: Date())
    cache.removeAll()
    searchRevision = UUID()
    scheduleCleanup()
  }

  private func clean(generation: UUID) async {
    defer { if cleanupGeneration == generation { cleanupTask = nil } }
    do {
      while cleanupGeneration == generation {
        try Task.checkCancellation()
        let database = try storage()
        guard try database.cleanupProgress().isPending else { return }
        let removed = try database.performCleanupSlice()
        for id in removed { cache.remove(id) }
        scheduleIndex()
        try await Task.sleep(for: Self.cleanupYield)
      }
    } catch is CancellationError { return } catch {
      cleanupFailure = error.localizedDescription
      fputs("Vault cleanup paused: \(error)\n", stderr)
    }
  }
}
