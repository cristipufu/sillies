import Foundation
import SilliesCore
import SilliesModelStore
import SilliesTextModels
import Testing

@testable import SilliesReasoning

struct NativeConversationModel {
  let id: String
  let backend: any ConversationBackend
  let stop: @Sendable () async -> Void

  static func prepare() async throws -> Self {
    let environment = ProcessInfo.processInfo.environment
    let id = try #require(environment["SILLIES_CONTINUITY_MODEL"])
    if id == "apple" {
      let backend = AppleReasoningBackend()
      try #require(await backend.availabilityNotice(localeIdentifier: "en") == nil)
      return .init(id: id, backend: backend, stop: { await backend.stop() })
    }
    let directory = try #require(environment["SILLIES_CONTINUITY_MODEL_ROOT"])
    let helper = try #require(environment["SILLIES_CONTINUITY_HELPER"])
    let manifest = try #require(TextModelCatalog.bundled().manifests.first { $0.modelID == id })
    let store = ModelStore(root: URL(fileURLWithPath: directory))
    try #require(try await store.isInstalled(manifest))
    let registry = try TextModelRegistry(
      store: store, providers: [MLXTextModelProvider(executable: URL(fileURLWithPath: helper))])
    return .init(
      id: id,
      backend: DownloadedReasoningBackend(manifest: manifest, store: store, registry: registry),
      stop: { await registry.stop() })
  }
}
