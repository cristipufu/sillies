import SilliesModelStore

/// Both optional model families share installation progress, cancellation and selection behavior.
typealias TextModelsPresentation = DownloadableModelsPresentation<TextModelManifest>

extension DownloadableModelsPresentation where Manifest == TextModelManifest {
  convenience init(environment: TextModelEnvironment) {
    self.init(
      environment: .init(
        store: environment.store,
        catalog: { try await environment.modelCatalog().manifests },
        selectedID: { await environment.selectedID() },
        select: { try await environment.select($0) },
        remove: { try await environment.remove($0) },
        stop: { await environment.stop() }, minimumMemoryGB: { $0.model.minimumMemoryGB }),
      selectedID: TextModelEnvironment.appleID)
  }
}
