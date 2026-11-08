import SilliesModelStore

typealias VoiceModelsPresentation = DownloadableModelsPresentation<TTSModelManifest>

extension DownloadableModelsPresentation where Manifest == TTSModelManifest {
  convenience init(environment: VoiceModelEnvironment) {
    self.init(
      environment: .init(
        store: environment.store,
        catalog: { try await environment.modelCatalog().manifests },
        selectedID: { await environment.selectedID() },
        select: { try await environment.select($0) },
        remove: { try await environment.remove($0) },
        minimumMemoryGB: { $0.model.minimumMemoryGB }),
      selectedID: VoiceModelEnvironment.disabledID)
  }
}
