import Foundation
import Observation
import SilliesCore
import SilliesModelStore

@MainActor @Observable
final class SpeechModelsPresentation {
  typealias State = ModelInstallationState
  private static let preferenceKey = "transcriptionModel"
  private static let diarizationPreferenceKey = "speakerDetectionModel"
  private(set) var selectedModelID: String
  private(set) var diarizationModelID: String?
  private(set) var manifests: [SpeechModelManifest] = []
  private(set) var states: [String: State] = [:]
  private(set) var isLoading = false
  private(set) var error: String?
  private(set) var rollbackModelIDs: Set<String> = []
  private var installedModelIDs: Set<String> = []
  let updates: ModelUpdatesPresentation?
  @ObservationIgnored private let store: ModelStore
  @ObservationIgnored private let registry: SpeechRuntimeRegistry
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

  init(
    store: ModelStore, registry: SpeechRuntimeRegistry, defaults: UserDefaults,
    updates: ModelUpdatesPresentation? = nil
  ) {
    self.store = store
    self.registry = registry
    self.defaults = defaults
    self.updates = updates
    selectedModelID = defaults.string(forKey: Self.preferenceKey) ?? SpeechModelDescriptor.apple.id
    diarizationModelID = defaults.string(forKey: Self.diarizationPreferenceKey)
  }

  func load() async {
    guard manifests.isEmpty, !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      manifests = try await registry.modelCatalog().manifests
      for manifest in manifests {
        do {
          try await refresh(manifest.model.id)
        } catch {
          states[manifest.model.id] = .failed(error.localizedDescription)
          report(error)
        }
      }
    } catch { report(error) }
    await updates?.load()
  }

  var availableUpdateCount: Int { manifests.filter { update(for: $0) != nil }.count }

  func update(for manifest: SpeechModelManifest) -> SpeechModelManifest? {
    guard installedModelIDs.contains(manifest.model.id),
      let entry = updates?.snapshot.entries[manifest.model.id],
      entry.installedRevision == manifest.model.revision
    else { return nil }
    return entry.candidate
  }

  func state(for id: String) -> State { states[id] ?? .absent }

  func useApple() { select(SpeechModelDescriptor.apple.id) }

  func use(_ manifest: SpeechModelManifest) {
    if manifest.model.isDiarizationModel {
      diarizationModelID = manifest.model.id
      defaults.set(manifest.model.id, forKey: Self.diarizationPreferenceKey)
      error = nil
    } else {
      select(manifest.model.id)
    }
  }

  func disableSpeakerDetection() {
    diarizationModelID = nil
    defaults.removeObject(forKey: Self.diarizationPreferenceKey)
  }

  func isSelected(_ manifest: SpeechModelManifest) -> Bool {
    (manifest.model.isDiarizationModel ? diarizationModelID : selectedModelID) == manifest.model.id
  }

  func retryPreparation(_ manifest: SpeechModelManifest) {
    perform(manifest) { [registry] in
      _ = try await registry.prepare(manifest.model.id)
    }
  }

  func download(_ manifest: SpeechModelManifest) {
    install(.download(manifest))
  }

  func installUpdate(_ manifest: SpeechModelManifest) {
    install(.update(manifest))
  }

  private enum Installation {
    case download(SpeechModelManifest)
    case update(SpeechModelManifest)
    var manifest: SpeechModelManifest {
      switch self {
      case .download(let manifest), .update(let manifest): manifest
      }
    }
  }

  private func install(_ installation: Installation) {
    let manifest = installation.manifest
    let id = manifest.model.id
    guard tasks[id] == nil else { return }
    states[id] = .downloading(0)
    tasks[id] = Task(priority: .utility) { [weak self, store, registry] in
      let (updates, continuation) = AsyncStream<ModelInstallationProgress>.makeStream(
        bufferingPolicy: .bufferingNewest(1))
      let delivery = Task { [weak self] in
        for await progress in updates {
          guard !Task.isCancelled else { return }
          let fraction = min(
            1, max(0, Double(progress.completedBytes) / Double(max(1, progress.totalBytes))))
          self?.states[id] =
            progress.phase == .verifying
            ? .verifying(fraction)
            : .downloading(fraction)
        }
      }
      defer {
        continuation.finish()
        delivery.cancel()
      }
      var installed = false
      do {
        switch installation {
        case .download:
          try await store.install(manifest) { continuation.yield($0) }
        case .update:
          let baseline = try await registry.modelCatalog().manifest(for: id)
          try await store.stageUpdate(manifest, replacing: baseline) { continuation.yield($0) }
        }
        installed = true
        self?.installedModelIDs.insert(id)
        continuation.finish()
        delivery.cancel()
        await delivery.value
        try Task.checkCancellation()
        switch installation {
        case .download:
          self?.states[id] = .preparing
          _ = try await registry.prepare(id)
        case .update:
          self?.states[id] = .validating
          try await registry.validateAndActivate(manifest)
          try await self?.refresh(id)
        }
        try Task.checkCancellation()
        self?.states[id] = .ready
      } catch {
        delivery.cancel()
        await delivery.value
        if Task.isCancelled {
          switch installation {
          case .download: self?.states[id] = installed ? .downloaded : .paused
          case .update: self?.states[id] = .downloaded
          }
        } else {
          switch installation {
          case .download:
            self?.states[id] =
              installed
              ? .preparationFailed(error.localizedDescription) : .failed(error.localizedDescription)
          case .update:
            self?.states[id] = .downloaded
          }
          self?.report(error)
        }
      }
      self?.tasks[id] = nil
    }
  }

  func rollBack(_ manifest: SpeechModelManifest) {
    let id = manifest.model.id
    guard tasks[id] == nil else { return }
    states[id] = .validating
    tasks[id] = Task(priority: .utility) { [weak self, registry] in
      do {
        try await registry.rollBack(id)
        try await self?.refresh(id)
      } catch {
        self?.states[id] = .downloaded
        self?.report(error)
      }
      self?.tasks[id] = nil
    }
  }

  private func refresh(_ id: String) async throws {
    let baseline = try await registry.modelCatalog().manifest(for: id)
    let current = try await store.currentManifest(baseline)
    if let index = manifests.firstIndex(where: { $0.model.id == id }) { manifests[index] = current }
    if try await store.isInstalled(current) {
      states[id] = .downloaded
      installedModelIDs.insert(id)
    } else {
      states[id] = .absent
      installedModelIDs.remove(id)
    }
    if try await store.previousManifest(baseline) != nil {
      rollbackModelIDs.insert(id)
    } else {
      rollbackModelIDs.remove(id)
    }
  }

  func pause(_ id: String) {
    states[id] = .cancelling
    tasks[id]?.cancel()
  }

  func remove(_ manifest: SpeechModelManifest) {
    guard tasks[manifest.model.id] == nil else { return }
    tasks[manifest.model.id] = Task(priority: .utility) { [weak self, store] in
      do {
        try await store.remove(manifest)
        self?.states[manifest.model.id] = .absent
        self?.installedModelIDs.remove(manifest.model.id)
        self?.rollbackModelIDs.remove(manifest.model.id)
        if self?.selectedModelID == manifest.model.id { self?.useApple() }
        if self?.diarizationModelID == manifest.model.id { self?.disableSpeakerDetection() }
      } catch { self?.report(error) }
      self?.tasks[manifest.model.id] = nil
    }
  }

  func stop() {
    updates?.stop()
    for task in tasks.values { task.cancel() }
  }

  private func select(_ id: String) {
    selectedModelID = id
    defaults.set(id, forKey: Self.preferenceKey)
    error = nil
  }

  private func perform(
    _ manifest: SpeechModelManifest, operation: @escaping @Sendable () async throws -> Void
  ) {
    let id = manifest.model.id
    guard tasks[id] == nil else { return }
    states[id] = .preparing
    tasks[id] = Task(priority: .utility) { [weak self] in
      do {
        try await operation()
        try Task.checkCancellation()
        self?.states[id] = .ready
      } catch is CancellationError { self?.states[id] = .downloaded } catch {
        self?.states[id] = .preparationFailed(error.localizedDescription)
        self?.report(error)
      }
      self?.tasks[id] = nil
    }
  }

  private func report(_ error: Error) {
    self.error = error.localizedDescription
    fputs("Transcription model: \(error.localizedDescription)\n", stderr)
  }
}
