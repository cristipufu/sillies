import Foundation
import Observation
import SilliesModelStore

typealias SearchModelDownloads = DownloadableModelsPresentation<SearchModelManifest>

@MainActor @Observable final class SearchModelsPresentation {
  let downloads: SearchModelDownloads
  private(set) var status = SearchIndexStatus.preparing
  private let environment: SearchModelEnvironment
  init(environment: SearchModelEnvironment) {
    self.environment = environment
    downloads = .init(
      environment: .init(
        store: environment.store,
        catalog: { try await environment.modelCatalog().manifests },
        selectedID: { await environment.selectedID() },
        select: { try await environment.select($0) },
        remove: { try await environment.remove($0) },
        stop: { await environment.stop() }, minimumMemoryGB: { $0.model.minimumMemoryGB }),
      selectedID: SearchModelEnvironment.appleID)
  }
  func observeStatus() async {
    await downloads.load()
    do {
      while !Task.isCancelled {
        status = try await environment.status()
        try await Task.sleep(for: .milliseconds(750))
      }
    } catch is CancellationError { return } catch { status = .failed(error.localizedDescription) }
  }
  func rebuild() async {
    do {
      try await environment.rebuild()
      status = try await environment.status()
    } catch { status = .failed(error.localizedDescription) }
  }
  func stop() { downloads.stop() }
}
