import Foundation
import Observation
import SilliesCore
import SilliesVault

/// A single visible-workspace observer; closing the window cancels its SwiftUI-owned task.
@MainActor @Observable final class VaultSearchPreparationModel {
  private static let refreshInterval: Duration = .seconds(2)
  private let library: VaultLibrary
  private var generation = UUID()
  private(set) var isPreparing = false
  private(set) var progress: SearchIndexProgress?
  private(set) var failure: String?
  private(set) var cleanup: VaultCleanupProgress?
  private(set) var cleanupFailure: String?

  init(library: VaultLibrary) { self.library = library }

  func observe() async {
    let token = UUID()
    generation = token
    while !Task.isCancelled, generation == token {
      do {
        let (progress, failure) = try await library.searchIndexStatus()
        let preparing = await library.isPreparingSearch
        let cleanup = try await library.cleanupStatus()
        guard !Task.isCancelled, generation == token else { return }
        self.progress = progress
        self.failure = failure
        isPreparing = preparing
        self.cleanup = cleanup.0
        cleanupFailure = cleanup.1
        try await Task.sleep(for: Self.refreshInterval)
      } catch is CancellationError { return } catch {
        guard !Task.isCancelled, generation == token else { return }
        failure = error.localizedDescription
        return
      }
    }
  }

  func retry() async { await library.retrySearchPreparation() }
  func retryCleanup() async { await library.resumeCleanup() }
}
