import Foundation
import SilliesInference
import SilliesModelStore

/// One voice runtime for the entire crew. Installation leases outlive all native model reads.
package actor TTSModelRegistry {
  package static let defaultIdleDuration: Duration = .seconds(60)
  private struct Loaded {
    let residencyID = UUID()
    let id: String
    let revision: String
    let model: any PreparedTTSModel
    let lease: InstalledModelLease
  }
  package enum Retention { case available, memoryPressure }
  private static let bytesPerGiB: UInt64 = 1_024 * 1_024 * 1_024
  private let store: ModelStore
  private let providers: [String: any TTSProvider]
  private let activity: InferenceActivity
  private var loaded: Loaded?
  private struct Work {
    let task: Task<Bool, Error>
    let kind: VoiceModelOperation.Kind
  }
  private var active: Work?
  private var idle: Task<Void, Never>?
  private var suspended = false
  private var retention = Retention.available
  private var lifetimes: [UUID: SpeechModelLifetime] = [:]
  private let lifetimeOwner = UUID()
  private let idleDuration: Duration

  package init(
    store: ModelStore, providers: [any TTSProvider], activity: InferenceActivity,
    idleDuration: Duration = TTSModelRegistry.defaultIdleDuration
  ) throws {
    guard Set(providers.map(\.id)).count == providers.count else {
      throw TTSError.unavailable(String(localized: "Duplicate voice provider registration."))
    }
    self.store = store
    self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    self.activity = activity
    self.idleDuration = idleDuration
  }

  package func synthesize(
    _ request: SpeechSynthesisRequest, using manifest: TTSModelManifest,
    receive: @escaping SynthesizedAudioSink
  ) async throws {
    try request.validate()
    _ = try await run(.synthesize(request, receive), using: manifest)
  }

  package func prepareVoiceIfPossible(
    _ voice: SpeechVoice, using manifest: TTSModelManifest, conversationID: UUID
  ) async throws -> Bool {
    try voice.validate()
    guard retention == .available else { return false }
    do {
      return try await run(.prepare(voice, conversationID: conversationID), using: manifest)
    } catch is CancellationError {
      try Task.checkCancellation()
      return false
    }
  }

  package func retain(for lifetime: SpeechModelLifetime) async {
    lifetimes[lifetime.id] = lifetime
    let id = lifetime.id
    await lifetime.onEnd(owner: lifetimeOwner) { [weak self] in await self?.endLifetime(id) }
  }

  private func endLifetime(_ id: UUID) { lifetimes[id] = nil }

  package func setRetention(_ retention: Retention) async {
    self.retention = retention
    guard retention == .memoryPressure else { return }
    if active?.kind == .preparation { active?.task.cancel() }
    if active == nil { await releaseModel() }
  }

  private func run(_ operation: VoiceModelOperation, using manifest: TTSModelManifest) async throws
    -> Bool
  {
    guard !suspended else { throw TTSError.interrupted }
    guard active == nil else { throw TTSError.busy }
    guard manifest.model.supports(language: operation.voice.language) else {
      throw TTSError.unsupportedLanguage
    }
    guard let voice = manifest.model.voices.first(where: { $0.id == operation.voice.id }),
      voice.supports(language: operation.voice.language)
    else { throw TTSError.unsupportedVoice }
    idle?.cancel()
    let cancellation = InferenceCancellation()
    let task = Task {
      try await self.perform(
        operation, manifest: manifest, cancellation: cancellation)
    }
    active = Work(task: task, kind: operation.kind)
    cancellation.install { task.cancel() }
    let result = await withTaskCancellationHandler {
      await task.result
    } onCancel: {
      task.cancel()
    }
    active = nil
    if retention == .memoryPressure { await releaseModel() } else { scheduleRelease() }
    return try result.get()
  }

  private func perform(
    _ operation: VoiceModelOperation, manifest: TTSModelManifest,
    cancellation: InferenceCancellation
  ) async throws -> Bool {
    let id = UUID()
    let reservation = InferenceReservation(
      conversationID: operation.conversationID, modelBytes: manifest.downloadBytes)
    switch operation.kind {
    case .preparation:
      guard
        await activity.claimVoicePreparation(
          id, reservation: reservation, cancel: { cancellation.cancel() })
      else {
        try Task.checkCancellation()
        return false
      }
    case .synthesis:
      try await admitSynthesis(id, reservation: reservation, cancellation: cancellation)
    }
    do {
      try Task.checkCancellation()
      await activity.prepareVoiceModel(reservation)
      let model = try await prepare(manifest)
      try await operation.run(on: model)
      try Task.checkCancellation()
      await activity.releaseSynthesis(id)
      return true
    } catch {
      await releaseModel()
      await activity.releaseSynthesis(id)
      try Task.checkCancellation()
      throw error
    }
  }

  private func admitSynthesis(
    _ id: UUID, reservation: InferenceReservation, cancellation: InferenceCancellation
  ) async throws {
    while true {
      try Task.checkCancellation()
      try await activity.waitForSynthesisAdmission()
      if await activity.claimSynthesis(
        id, reservation: reservation, cancel: { cancellation.cancel() })
      {
        return
      }
    }
  }

  private func prepare(_ manifest: TTSModelManifest) async throws -> any PreparedTTSModel {
    if let loaded, loaded.id == manifest.modelID, loaded.revision == manifest.revision {
      return loaded.model
    }
    await releaseModel()
    guard let provider = providers[manifest.model.providerID] else {
      throw TTSError.unavailable(
        String(localized: "This voice model needs a newer version of Sillies."))
    }
    guard
      ProcessInfo.processInfo.physicalMemory / Self.bytesPerGiB >= manifest.model.minimumMemoryGB
    else {
      throw TTSError.unavailable(
        String(
          localized:
            "This voice model needs at least \(manifest.model.minimumMemoryGB) GB of memory."))
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
      let resident = Loaded(
        id: manifest.modelID, revision: manifest.revision, model: model, lease: lease)
      loaded = resident
      let residencyID = resident.residencyID
      await activity.rememberVoiceModel(
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
    lifetimes.removeAll()
    let task = active?.task
    task?.cancel()
    await releaseModel()
    if let task { _ = await task.result }
  }

  private func releaseModel() async {
    let previous = loaded
    loaded = nil
    await previous?.model.stop()
    await previous?.lease.close()
    if let previous { await activity.forgetVoiceModel(previous.residencyID) }
  }
  private func evict(_ id: UUID) async {
    guard loaded?.residencyID == id else { return }
    await releaseModel()
  }

  private func scheduleRelease() {
    idle?.cancel()
    guard let id = loaded?.residencyID else { return }
    let delay = idleDuration
    idle = Task { [weak self] in
      do { try await Task.sleep(for: delay) } catch { return }
      await self?.releaseIfIdle(id)
    }
  }

  private func releaseIfIdle(_ id: UUID) async {
    for (key, lifetime) in lifetimes where await !lifetime.isActive {
      lifetimes[key] = nil
    }
    guard !Task.isCancelled, active == nil, loaded?.residencyID == id else { return }
    if retention == .available, !lifetimes.isEmpty {
      scheduleRelease()
    } else {
      await releaseModel()
    }
  }
}
