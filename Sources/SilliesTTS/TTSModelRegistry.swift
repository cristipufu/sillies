import Foundation
import SilliesInference
import SilliesModelStore

/// One voice runtime for the entire crew. Installation leases outlive all native model reads.
package actor TTSModelRegistry {
  private struct Loaded {
    let id: String
    let revision: String
    let model: any PreparedTTSModel
    let lease: InstalledModelLease
  }
  private static let idleDuration: Duration = .seconds(60)
  private static let bytesPerGiB: UInt64 = 1_024 * 1_024 * 1_024
  private let store: ModelStore
  private let providers: [String: any TTSProvider]
  private let activity: InferenceActivity
  private var loaded: Loaded?
  private var active: Task<Void, Error>?
  private var idle: Task<Void, Never>?
  private var suspended = false

  package init(store: ModelStore, providers: [any TTSProvider], activity: InferenceActivity) throws
  {
    guard Set(providers.map(\.id)).count == providers.count else {
      throw TTSError.unavailable("Duplicate voice provider registration.")
    }
    self.store = store
    self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    self.activity = activity
  }

  package func synthesize(
    _ request: SpeechSynthesisRequest, using manifest: TTSModelManifest,
    receive: @escaping SynthesizedAudioSink
  ) async throws {
    try request.validate()
    guard !suspended else { throw TTSError.interrupted }
    guard active == nil else { throw TTSError.busy }
    guard manifest.model.supports(language: request.language) else {
      throw TTSError.unsupportedLanguage
    }
    guard let voice = manifest.model.voices.first(where: { $0.id == request.voiceID }),
      voice.supports(language: request.language)
    else { throw TTSError.unsupportedVoice }
    idle?.cancel()
    let cancellation = InferenceCancellation()
    let task = Task {
      try await self.perform(
        request, manifest: manifest, cancellation: cancellation, receive: receive)
    }
    active = task
    cancellation.install { task.cancel() }
    defer {
      active = nil
      scheduleRelease()
    }
    try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  private func perform(
    _ request: SpeechSynthesisRequest, manifest: TTSModelManifest,
    cancellation: InferenceCancellation, receive: @escaping SynthesizedAudioSink
  ) async throws {
    let id = UUID()
    guard await activity.claimSynthesis(id, cancel: { cancellation.cancel() }) else {
      throw TTSError.busy
    }
    do {
      try Task.checkCancellation()
      let model = try await prepare(manifest)
      try await model.synthesize(request, receive: receive)
      try Task.checkCancellation()
      await activity.releaseSynthesis(id)
    } catch {
      await releaseModel()
      await activity.releaseSynthesis(id)
      throw error
    }
  }

  private func prepare(_ manifest: TTSModelManifest) async throws -> any PreparedTTSModel {
    if let loaded, loaded.id == manifest.modelID, loaded.revision == manifest.revision {
      return loaded.model
    }
    await releaseModel()
    guard let provider = providers[manifest.model.providerID] else {
      throw TTSError.unavailable("This voice model needs a newer version of Sillies.")
    }
    guard
      ProcessInfo.processInfo.physicalMemory / Self.bytesPerGiB >= manifest.model.minimumMemoryGB
    else {
      throw TTSError.unavailable(
        "This voice model needs at least \(manifest.model.minimumMemoryGB) GB of memory.")
    }
    let lease = try await store.acquire(manifest)
    do {
      let resources = manifest.artifacts.map {
        TTSModelResource(path: $0.path, byteCount: $0.byteCount, sha256: $0.sha256)
      }
      let model = try await provider.prepare(
        .init(
          directory: lease.directory, providerID: provider.id,
          variant: manifest.model.runtimeVariant,
          resources: resources))
      if Task.isCancelled {
        await model.stop()
        throw CancellationError()
      }
      loaded = .init(id: manifest.modelID, revision: manifest.revision, model: model, lease: lease)
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
    await releaseModel()
    if let task { _ = await task.result }
  }

  private func releaseModel() async {
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
      await self?.releaseModel()
    }
  }
}
