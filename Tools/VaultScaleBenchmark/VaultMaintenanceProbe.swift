import Foundation
import SilliesCore
import SilliesPersistence
import SilliesVault

extension VaultScaleBenchmark {
  /// Run only on a disposable copy: this measures a durable deletion request, not a complete purge.
  static func maintenance(_ library: VaultLibrary, mutation: VaultMutation) async throws {
    let started = ContinuousClock.now
    let snapshot = try await library.commit(mutation)
    let commit = milliseconds(started.duration(to: .now))
    let pageStarted = ContinuousClock.now
    let page = try await library.workspacePage(.init())
    let elapsed = milliseconds(pageStarted.duration(to: .now))
    let cleanup = try await library.cleanupStatus()
    try emit(
      MaintenanceResult(
        commitMilliseconds: commit, pageMilliseconds: elapsed,
        visibleTotal: snapshot.page.total, returned: page.records.count,
        pending: cleanup.0.isPending, loadedBodies: try await library.metrics().loadedBodies))
  }
}

private struct MaintenanceResult: Encodable {
  let commitMilliseconds: Double
  let pageMilliseconds: Double
  let visibleTotal: Int
  let returned: Int
  let pending: Bool
  let loadedBodies: Int
}
