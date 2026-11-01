import Foundation
import SilliesModelStore
import SilliesTTS

/// Installation and selection live here; Chat only receives the speech-output capability.
actor VoiceModelEnvironment {
  static let disabledID = "none"
  let store: ModelStore
  private let registry: TTSModelRegistry
  private let savePreference: @MainActor @Sendable (String) -> Void
  private var selected: String
  private var catalog: TTSModelCatalog?

  init(
    store: ModelStore, registry: TTSModelRegistry, selectedID: String,
    savePreference: @escaping @MainActor @Sendable (String) -> Void
  ) {
    self.store = store
    self.registry = registry
    selected = selectedID
    self.savePreference = savePreference
  }

  func modelCatalog() throws -> TTSModelCatalog {
    if let catalog { return catalog }
    let catalog = try TTSModelCatalog.bundled()
    self.catalog = catalog
    return catalog
  }
  func selectedID() -> String { selected }
  func selectedModel() throws -> TTSModelManifest? {
    guard selected != Self.disabledID else { return nil }
    guard let manifest = try modelCatalog().manifests.first(where: { $0.modelID == selected })
    else {
      throw TTSError.unavailable(
        String(localized: "Choose an installed voice model in Settings → Voices."))
    }
    return manifest
  }
  func select(_ id: String) async throws {
    if id != Self.disabledID {
      guard let manifest = try modelCatalog().manifests.first(where: { $0.modelID == id }),
        try await store.isInstalled(manifest)
      else { throw ModelStoreError.notInstalled }
    }
    await registry.stop()
    selected = id
    await savePreference(id)
  }
  func remove(_ manifest: TTSModelManifest) async throws {
    await registry.stop()
    try await store.remove(manifest)
    if selected == manifest.modelID { try await select(Self.disabledID) }
  }
  func synthesize(
    _ request: SpeechSynthesisRequest, using manifest: TTSModelManifest,
    receive: @escaping SynthesizedAudioSink
  ) async throws {
    try await registry.synthesize(request, using: manifest, receive: receive)
  }
  func resume() async { await registry.resume() }
  func stop() async { await registry.suspend() }
}
