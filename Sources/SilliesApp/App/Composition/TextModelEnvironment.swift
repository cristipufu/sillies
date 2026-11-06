import Foundation
import SilliesDiagnostics
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
  private let memoryPressure = MemoryPressureMonitor()
  private let apple = AppleReasoningBackend()
  private let diagnostics: DiagnosticSink
  private let calibration: TextCalibrationStore?

  init(
    store: ModelStore, preference: TextModelPreference, providers: [any TextModelProvider],
    diagnostics: DiagnosticSink = .disabled, calibration: TextCalibrationStore? = nil
  ) {
    self.preference = preference
    selected = preference.selectedID
    self.store = store
    self.diagnostics = diagnostics
    self.calibration = calibration
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
    await apple.stop()
    selected = id
    await preference.save(id)
  }

  func backend(overriding selection: String? = nil) async -> any ReasoningBackend {
    let modelID = selection ?? selected
    do {
      let registry = try registry.get()
      await memoryPressure.start { [apple] pressure in
        let retention: TextModelRegistry.Retention =
          pressure == .constrained ? .memoryPressure : .available
        await registry.setRetention(retention)
        await apple.setRetention(retention)
      }
    } catch {
      return UnavailableReasoningBackend(notice: error.localizedDescription)
    }
    guard modelID != Self.appleID else {
      diagnostics.record(
        .init(.inference, .modelSelected).using(model: Self.appleID, provider: "apple"))
      return apple
    }
    do {
      guard let manifest = try modelCatalog().manifests.first(where: { $0.modelID == modelID })
      else {
        throw TextModelError.unavailable(
          String(
            localized:
              "The selected text model is no longer available. Choose another in Settings → Local AI."
          ))
      }
      diagnostics.record(
        .init(.inference, .modelSelected).using(
          model: manifest.model.id, provider: manifest.model.providerID))
      return DownloadedReasoningBackend(
        manifest: await calibrated(manifest), store: store, registry: try registry.get())
    } catch { return UnavailableReasoningBackend(notice: error.localizedDescription) }
  }

  func remove(_ manifest: TextModelManifest) async throws {
    try await registry.get().stop()
    try await store.remove(manifest)
    if selected == manifest.modelID { try await select(Self.appleID) }
  }

  private func calibrated(_ manifest: TextModelManifest) async -> TextModelManifest {
    guard let calibration else { return manifest }
    do { return try await calibration.resolve(manifest) } catch {
      fputs("Text calibration unavailable; using catalog settings: \(error)\n", stderr)
      return manifest
    }
  }

  func setActivity(_ activity: Activity) async {
    do {
      switch activity {
      case .active: try await registry.get().resume()
      case .suspended:
        await memoryPressure.stop()
        await apple.stop()
        try await registry.get().suspend()
      }
    } catch { fputs("Local text model activity failed: \(error.localizedDescription)\n", stderr) }
  }

  func stop() async {
    await memoryPressure.stop()
    await apple.stop()
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
