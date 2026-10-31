import Foundation
import SilliesModelStore
import SilliesReasoning
import SilliesTextModels

/// Composition root for local text models. Model identity is data; views never construct runtimes.
actor TextModelEnvironment {
  enum Activity { case active, suspended }
  static let appleID = "apple"
  let store: ModelStore
  private let preference: TextModelPreference
  private let registry: Result<TextModelRegistry, Error>
  private var catalog: TextModelCatalog?
  private var selected: String

  init(store: ModelStore, preference: TextModelPreference, providers: [any TextModelProvider]) {
    self.preference = preference
    selected = preference.selectedID
    self.store = store
    registry = Result { try TextModelRegistry(store: store, providers: providers) }
  }

  func modelCatalog() throws -> TextModelCatalog {
    if let catalog { return catalog }
    let result = try TextModelCatalog.bundled()
    catalog = result
    return result
  }
  func selectedID() -> String { selected }

  func select(_ id: String) async throws {
    if id != Self.appleID {
      guard let manifest = try modelCatalog().manifests.first(where: { $0.modelID == id }),
        try await store.isInstalled(manifest)
      else { throw ModelStoreError.notInstalled }
    }
    try await registry.get().stop()
    selected = id
    await preference.save(id)
  }

  func backend() -> any ReasoningBackend {
    guard selected != Self.appleID else { return AppleReasoningBackend() }
    do {
      guard let manifest = try modelCatalog().manifests.first(where: { $0.modelID == selected })
      else {
        throw TextModelError.unavailable(
          "The selected text model is no longer available. Choose another in Settings → Local AI.")
      }
      return DownloadedReasoningBackend(
        manifest: manifest, store: store, registry: try registry.get())
    } catch { return UnavailableReasoningBackend(notice: error.localizedDescription) }
  }

  func remove(_ manifest: TextModelManifest) async throws {
    try await registry.get().stop()
    try await store.remove(manifest)
    if selected == manifest.modelID { try await select(Self.appleID) }
  }

  func setActivity(_ activity: Activity) async {
    do {
      switch activity {
      case .active: try await registry.get().resume()
      case .suspended: try await registry.get().suspend()
      }
    } catch { fputs("Local text model activity failed: \(error.localizedDescription)\n", stderr) }
  }

  func stop() async {
    do { try await registry.get().suspend() } catch {
      fputs("Local text model shutdown failed: \(error.localizedDescription)\n", stderr)
    }
  }
}

private struct UnavailableReasoningBackend: ReasoningBackend {
  let notice: String
  func availabilityNotice(localeIdentifier: String?) async -> String? { notice }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> String {
    throw TextModelError.unavailable(notice)
  }
}
