import Foundation
import SilliesInference
import SilliesModelStore

/// Owns one runtime and its installation lease. Speech can preempt and release the GPU worker.
package actor TextModelRegistry {
  private struct Loaded {
    let id: String
    let model: any PreparedTextModel
    let lease: InstalledModelLease
  }
  private static let idleDuration: Duration = .seconds(60)
  private let store: ModelStore
  private let providers: [String: any TextModelProvider]
  private let activity: InferenceActivity
  private var suspended = false
  private var loaded: Loaded?
  private var active: Task<String, Error>?
  private var idle: Task<Void, Never>?

  package init(
    store: ModelStore, providers: [any TextModelProvider], activity: InferenceActivity = .shared
  ) throws {
    guard Set(providers.map(\.id)).count == providers.count else {
      throw TextModelError.unavailable("Duplicate text model provider registration.")
    }
    self.store = store
    self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    self.activity = activity
  }

  package func generate(_ request: TextGenerationRequest, using manifest: TextModelManifest)
    async throws -> String
  {
    guard !suspended else { throw TextModelError.interrupted }
    guard active == nil else { throw TextModelError.busy }
    idle?.cancel()
    let task = Task { try await perform(request, using: manifest) }
    active = task
    defer {
      active = nil
      scheduleRelease()
    }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  private func perform(_ request: TextGenerationRequest, using manifest: TextModelManifest)
    async throws -> String
  {
    while true {
      try Task.checkCancellation()
      try await activity.waitForSpeech()
      let id = UUID()
      let cancellation = InferenceCancellation()
      guard await activity.claimText(id, cancel: { cancellation.cancel() }) else { continue }
      let attempt = Task { () throws -> String in
        try Task.checkCancellation()
        let model = try await prepare(manifest)
        try Task.checkCancellation()
        return try await model.generate(request)
      }
      cancellation.install { attempt.cancel() }
      do {
        let result = try await withTaskCancellationHandler {
          try await attempt.value
        } onCancel: {
          attempt.cancel()
        }
        await activity.releaseText(id)
        try Task.checkCancellation()
        return result
      } catch {
        await releaseLoadedModel()
        await activity.releaseText(id)
        try Task.checkCancellation()
        if attempt.isCancelled { continue }
        throw error
      }
    }
  }

  private func prepare(_ manifest: TextModelManifest) async throws -> any PreparedTextModel {
    if let loaded, loaded.id == manifest.modelID { return loaded.model }
    await releaseLoadedModel()
    guard let provider = providers[manifest.model.providerID] else {
      throw TextModelError.unavailable("This text model needs a newer version of Sillies.")
    }
    let gibibyte: UInt64 = 1024 * 1024 * 1024
    guard ProcessInfo.processInfo.physicalMemory / gibibyte >= manifest.model.minimumMemoryGB else {
      throw TextModelError.unavailable(
        "This model requires at least \(manifest.model.minimumMemoryGB) GB of memory.")
    }
    let lease = try await store.acquire(manifest)
    let model = try await provider.prepare(
      .init(directory: lease.directory, contextTokens: manifest.model.contextTokens))
    loaded = Loaded(id: manifest.modelID, model: model, lease: lease)
    return model
  }

  package func suspend() async {
    suspended = true
    await stop()
  }
  package func resume() { suspended = false }

  package func stop() async {
    idle?.cancel()
    idle = nil
    let task = active
    task?.cancel()
    await releaseLoadedModel()
    if let task { _ = await task.result }
  }

  private func releaseLoadedModel() async {
    let previous = loaded
    loaded = nil
    await previous?.model.stop()
    await previous?.lease.close()
  }

  private func scheduleRelease() {
    idle?.cancel()
    guard loaded != nil else { return }
    idle = Task { [weak self] in
      do { try await Task.sleep(for: Self.idleDuration) } catch { return }
      await self?.releaseLoadedModel()
    }
  }
}
