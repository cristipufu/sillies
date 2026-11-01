import Foundation
import SilliesInference
import SilliesModelStore

/// Owns one runtime and its installation lease. Speech can preempt and release the GPU worker.
package actor TextModelRegistry {
  private struct Loaded {
    let residencyID = UUID()
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
  private var active: Task<TextGenerationOutput, Error>?
  private var idle: Task<Void, Never>?

  package init(
    store: ModelStore, providers: [any TextModelProvider], activity: InferenceActivity = .shared
  ) throws {
    guard Set(providers.map(\.id)).count == providers.count else {
      throw TextModelError.unavailable(
        String(localized: "Duplicate text model provider registration."))
    }
    self.store = store
    self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    self.activity = activity
  }

  package func generate(_ request: TextGenerationRequest, using manifest: TextModelManifest)
    async throws -> String
  {
    let output = try await complete(request, using: manifest)
    guard output.calls.isEmpty else { throw TextModelError.invalidResponse }
    return output.text
  }
  package func complete(_ request: TextGenerationRequest, using manifest: TextModelManifest)
    async throws -> TextGenerationOutput
  {
    try await stream(request, using: manifest, receive: { _ in })
  }
  package func stream(
    _ request: TextGenerationRequest, using manifest: TextModelManifest,
    receive: @escaping TextDeltaSink
  ) async throws -> TextGenerationOutput {
    guard !suspended else { throw TextModelError.interrupted }
    guard active == nil else { throw TextModelError.busy }
    idle?.cancel()
    let task = Task { try await perform(request, using: manifest, receive: receive) }
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

  private func perform(
    _ request: TextGenerationRequest, using manifest: TextModelManifest,
    receive: @escaping TextDeltaSink
  )
    async throws -> TextGenerationOutput
  {
    let delivery = TextStreamDelivery(receive: receive)
    let reservation = InferenceReservation(
      conversationID: request.conversationID, modelBytes: manifest.downloadBytes)
    while true {
      try Task.checkCancellation()
      try await activity.waitForTextAdmission(reservation)
      let id = UUID()
      let cancellation = InferenceCancellation()
      guard
        await activity.claimText(id, reservation: reservation, cancel: { cancellation.cancel() })
      else { continue }
      let attempt = Task { () throws -> TextGenerationOutput in
        try Task.checkCancellation()
        await activity.prepareTextModel(reservation)
        let model = try await prepare(manifest)
        try Task.checkCancellation()
        return try await model.stream(request, receive: delivery.append)
      }
      cancellation.install { attempt.cancel() }
      do {
        let result = try await withTaskCancellationHandler {
          try await attempt.value
        } onCancel: {
          attempt.cancel()
        }
        if await activity.requiresTextEviction(id) { await releaseLoadedModel() }
        await activity.releaseText(id)
        try Task.checkCancellation()
        return result
      } catch TextModelError.contextLimit {
        if await activity.requiresTextEviction(id) { await releaseLoadedModel() }
        await activity.releaseText(id)
        try Task.checkCancellation()
        throw TextModelError.contextLimit
      } catch {
        await releaseLoadedModel()
        await activity.releaseText(id)
        try Task.checkCancellation()
        if attempt.isCancelled {
          guard await !delivery.hasOutput else { throw CancellationError() }
          continue
        }
        throw error
      }
    }
  }

  private func prepare(_ manifest: TextModelManifest) async throws -> any PreparedTextModel {
    if let loaded, loaded.id == manifest.modelID { return loaded.model }
    await releaseLoadedModel()
    guard let provider = providers[manifest.model.providerID] else {
      throw TextModelError.unavailable(
        String(localized: "This text model needs a newer version of Sillies."))
    }
    let gibibyte: UInt64 = 1024 * 1024 * 1024
    guard ProcessInfo.processInfo.physicalMemory / gibibyte >= manifest.model.minimumMemoryGB else {
      throw TextModelError.unavailable(
        String(
          localized: "This model requires at least \(manifest.model.minimumMemoryGB) GB of memory.")
      )
    }
    let memoryLimit = try TextModelMemoryBudget.allocation(
      weightBytes: manifest.downloadBytes, physicalMemory: ProcessInfo.processInfo.physicalMemory)
    let lease = try await store.acquire(manifest)
    do {
      let model = try await provider.prepare(
        .init(
          directory: lease.directory, contextTokens: manifest.model.contextTokens,
          memoryLimitBytes: memoryLimit))
      if Task.isCancelled {
        await model.stop()
        throw CancellationError()
      }
      let resident = Loaded(id: manifest.modelID, model: model, lease: lease)
      loaded = resident
      let residencyID = resident.residencyID
      await activity.rememberTextModel(
        id: residencyID,
        reservation: .init(modelBytes: manifest.downloadBytes)
      ) { [weak self] in
        await self?.evict(residencyID)
      }
      return model
    } catch {
      await lease.close()
      throw error
    }
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
    if let previous { await activity.forgetTextModel(previous.residencyID) }
  }
  private func evict(_ id: UUID) async {
    guard loaded?.residencyID == id else { return }
    await releaseLoadedModel()
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
