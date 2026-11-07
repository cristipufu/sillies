import Foundation
import Observation
import SilliesCore
import SilliesVault

/// Only one result's expanded matches are retained in the workspace.
@MainActor @Observable final class VaultPassageMatchesModel {
  private let library: VaultLibrary
  private(set) var recordID: UUID?
  private(set) var passages: [VaultPassageMatch] = []
  private(set) var isLoading = false
  private(set) var error: String?
  @ObservationIgnored private var task: Task<Void, Never>?
  private var request = UUID()
  init(library: VaultLibrary) { self.library = library }
  func toggle(_ id: UUID, query: VaultWorkspaceQuery) {
    let wasOpen = recordID == id
    stop()
    guard !wasOpen else { return }
    recordID = id
    isLoading = true
    let token = request
    task = Task { [weak self, library] in
      defer { if self?.request == token { self?.isLoading = false } }
      do {
        let passages = try await library.matchingPassages(recordID: id, query: query)
        guard let self, request == token, !Task.isCancelled else { return }
        self.passages = passages
      } catch is CancellationError { return } catch {
        guard self?.request == token, !Task.isCancelled else { return }
        self?.error = error.localizedDescription
      }
    }
  }
  func stop() {
    request = UUID()
    task?.cancel()
    task = nil
    recordID = nil
    passages = []
    error = nil
    isLoading = false
  }
  isolated deinit { task?.cancel() }
}
