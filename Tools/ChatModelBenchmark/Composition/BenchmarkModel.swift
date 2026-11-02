import Foundation
import SilliesModelStore
import SilliesReasoning
import SilliesTextModels

struct BenchmarkModel {
  struct Metadata: Encodable, Sendable {
    let id: String
    let revision: String
    let contextTokens: Int
    let reasoningTokenReserve: Int
    let summaryReasoningTokenReserve: Int
    let operatingSystem: String
    let memoryBytes: UInt64
    let processors: Int
  }
  let backend: any ConversationBackend
  let inference: BenchmarkInferenceTrace
  let metadata: Metadata
  let stop: @Sendable () async -> Void

  static func prepare(_ plan: BenchmarkPlan) async throws -> Self {
    let inference = BenchmarkInferenceTrace()
    if plan.model == "apple" {
      let backend = AppleReasoningBackend()
      return .init(
        backend: backend, inference: inference,
        metadata: metadata(id: "apple", revision: "system-managed", backend: backend),
        stop: { await backend.stop() })
    }
    guard
      let manifest = try TextModelCatalog.bundled().manifests.first(where: {
        $0.modelID == plan.model
      })
    else {
      throw TextModelError.unavailable("Unknown catalog model: \(plan.model)")
    }
    let store = ModelStore(root: URL(fileURLWithPath: plan.modelDirectory))
    guard try await store.isInstalled(manifest) else {
      throw TextModelError.unavailable("Model is not installed: \(plan.model)")
    }
    let registry = try TextModelRegistry(
      store: store,
      providers: [
        BenchmarkTextProvider(
          base: MLXTextModelProvider(executable: URL(fileURLWithPath: plan.helper)),
          trace: inference)
      ]
    )
    let backend = DownloadedReasoningBackend(manifest: manifest, store: store, registry: registry)
    return .init(
      backend: backend, inference: inference,
      metadata: metadata(id: plan.model, revision: manifest.revision, backend: backend),
      stop: { await registry.stop() })
  }

  private static func metadata(id: String, revision: String, backend: any ConversationBackend)
    -> Metadata
  {
    .init(
      id: id, revision: revision, contextTokens: backend.contextWindowTokens,
      reasoningTokenReserve: backend.reasoningTokenReserve,
      summaryReasoningTokenReserve: backend.reasoningTokenReserve(for: .summary),
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      memoryBytes: ProcessInfo.processInfo.physicalMemory,
      processors: ProcessInfo.processInfo.activeProcessorCount)
  }
}
