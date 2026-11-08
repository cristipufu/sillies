import Foundation
import SilliesCore
import SilliesModelStore
import SilliesModelValidation
import SilliesSpeech

/// The composition root registers providers. Runtime selection never branches on model names.
actor SpeechRuntimeRegistry {
  final class Runtime: PreparedSpeechModel, PreparedDiarizationModel {
    enum Engine: Sendable {
      case transcription(any PreparedSpeechModel)
      case diarization(any PreparedDiarizationModel)
    }
    private let engine: Engine
    private let lease: InstalledModelLease?
    init(model: any PreparedSpeechModel, lease: InstalledModelLease?) {
      self.engine = .transcription(model)
      self.lease = lease
    }
    init(engine: Engine, lease: InstalledModelLease?) {
      self.engine = engine
      self.lease = lease
    }
    func makeChannel(_ request: SpeechChannelRequest) async throws -> any LocalSpeechChannel {
      guard case .transcription(let model) = engine else { throw ModelStoreError.unknownModel }
      return RuntimeSpeechChannel(channel: try await model.makeChannel(request), runtime: self)
    }
    func makeChannel(_ request: SpeakerDiarizationRequest) async throws -> any LocalSpeechChannel {
      guard case .diarization(let model) = engine else { throw ModelStoreError.unknownModel }
      return RuntimeSpeechChannel(channel: try await model.makeChannel(request), runtime: self)
    }
    func validate() async throws {
      switch engine {
      case .transcription(let model): try await model.validate()
      case .diarization(let model): try await model.validate()
      }
    }
  }
  private let store: ModelStore
  private let providers: [String: any SpeechProvider]
  private let diarizationProviders: [String: any DiarizationProvider]
  private var catalog: SpeechModelCatalog?
  private weak var loaded: Runtime?
  private struct Identity: Hashable {
    let id: String
    let revision: String
    init(_ model: SpeechModelDescriptor) {
      id = model.id
      revision = model.revision
    }
  }
  private var loadedIdentity: Identity?
  private var validating = false
  private struct Preparation {
    let task: Task<Void, Never>
    var waiters: [UUID: CheckedContinuation<Runtime, Error>]
  }
  // At most one downloaded runtime and an independent Apple fallback may load together.
  // A cancelled native load keeps its slot until it returns, preventing duplicate compiles.
  private var preparations: [Identity: Preparation] = [:]

  init(
    store: ModelStore, providers: [any SpeechProvider],
    diarizationProviders: [any DiarizationProvider] = []
  ) throws {
    guard Set(providers.map(\.id)).count == providers.count,
      Set(diarizationProviders.map(\.id)).count == diarizationProviders.count
    else {
      throw SpeechError.unavailable(
        String(localized: "Duplicate speech or speaker provider registration."))
    }
    self.store = store
    self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    self.diarizationProviders = Dictionary(
      uniqueKeysWithValues: diarizationProviders.map { ($0.id, $0) })
  }

  func modelCatalog() throws -> SpeechModelCatalog {
    if let catalog { return catalog }
    let value = try SpeechModelCatalog.bundled()
    catalog = value
    return value
  }

  func languages(for id: String) async throws -> SpeechLanguageCatalog {
    let model: SpeechModelDescriptor
    let availability: SpeechLanguageRequest.Availability
    if id == SpeechModelDescriptor.apple.id {
      model = .apple
      availability = .installed
    } else {
      let manifest = try await currentManifest(id)
      model = manifest.model
      availability = try await store.isInstalled(manifest) ? .installed : .missing
    }
    guard !model.isDiarizationModel, let provider = providers[model.providerID] else {
      throw ModelStoreError.unknownModel
    }
    try checkHardware(model)
    return try await provider.languages(.init(model: model, availability: availability))
  }

  func currentManifest(_ id: String) async throws -> SpeechModelManifest {
    try await store.currentManifest(modelCatalog().manifest(for: id))
  }

  func validateAndActivate(_ candidate: SpeechModelManifest) async throws {
    guard preparations.isEmpty, !validating else { throw ModelStoreError.busy }
    validating = true
    defer { validating = false }
    let baseline = try modelCatalog().manifest(for: candidate.model.id)
    let current = try await store.currentManifest(baseline)
    let reference = try await store.acquire(current)
    let lease = try await store.acquire(candidate)
    let bundles = compiledBundles(in: current)
    guard !bundles.isEmpty, bundles == compiledBundles(in: candidate) else {
      throw ModelUpdateError.layoutChanged
    }
    try await ModelInterfaceValidator.validate(
      installed: reference.directory, candidate: lease.directory, bundles: bundles)
    let engine = try await prepareEngine(.init(model: candidate.model, directory: lease.directory))
    let runtime = Runtime(engine: engine, lease: lease)
    try await runtime.validate()
    try Task.checkCancellation()
    try await store.activate(
      candidate, replacing: baseline, validatedLease: lease, referenceLease: reference)
    loaded = nil
    loadedIdentity = nil
    withExtendedLifetime(runtime) {}
  }

  func rollBack(_ id: String) async throws {
    try await store.rollBack(modelCatalog().manifest(for: id))
    loaded = nil
    loadedIdentity = nil
  }

  private func compiledBundles(in manifest: SpeechModelManifest) -> [String] {
    Set(
      manifest.artifacts.compactMap { artifact in
        artifact.path.range(of: ".mlmodelc").map { String(artifact.path[..<$0.upperBound]) }
      }
    ).sorted()
  }

  func prepare(_ id: String) async throws -> Runtime {
    let manifest: SpeechModelManifest?
    if id == SpeechModelDescriptor.apple.id {
      manifest = nil
    } else {
      manifest = try await currentManifest(id)
    }
    return try await prepare(manifest: manifest)
  }

  func prepare(_ model: SpeechModelDescriptor) async throws -> Runtime {
    let manifest: SpeechModelManifest?
    if model.isSystemManaged {
      manifest = nil
    } else {
      let baseline = try modelCatalog().manifest(for: model.id)
      manifest = try await store.manifest(revision: model.revision, baseline: baseline)
    }
    return try await prepare(manifest: manifest)
  }

  private func prepare(manifest: SpeechModelManifest?) async throws -> Runtime {
    try Task.checkCancellation()
    let identity = Identity(manifest?.model ?? .apple)
    if loadedIdentity == identity, let loaded { return loaded }
    let token = UUID()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      let runtime = try await withCheckedThrowingContinuation { continuation in
        do { try startPreparation(manifest, waiter: token, continuation: continuation) } catch {
          continuation.resume(throwing: error)
        }
      }
      try Task.checkCancellation()
      return runtime
    } onCancel: {
      Task { await self.releaseWaiter(token) }
    }
  }

  private func startPreparation(
    _ manifest: SpeechModelManifest?, waiter: UUID,
    continuation: CheckedContinuation<Runtime, Error>
  ) throws {
    let identity = Identity(manifest?.model ?? .apple)
    if var preparation = preparations[identity] {
      guard !preparation.task.isCancelled else { throw ModelStoreError.busy }
      preparation.waiters[waiter] = continuation
      preparations[identity] = preparation
      return
    }
    // Native speech remains usable while a downloaded model specializes or is validated.
    guard manifest == nil || (preparations.isEmpty && !validating) else {
      throw ModelStoreError.busy
    }
    let task = Task(priority: .utility) {
      do {
        let runtime = try await loadRuntime(manifest)
        try Task.checkCancellation()
        completePreparation(identity, result: .success(runtime))
      } catch {
        completePreparation(identity, result: .failure(error))
      }
    }
    preparations[identity] = Preparation(task: task, waiters: [waiter: continuation])
  }

  private func loadRuntime(_ manifest: SpeechModelManifest?) async throws -> Runtime {
    let lease: InstalledModelLease?
    if let manifest { lease = try await store.acquire(manifest) } else { lease = nil }
    try Task.checkCancellation()
    let request = SpeechPreparation(model: manifest?.model ?? .apple, directory: lease?.directory)
    return Runtime(engine: try await prepareEngine(request), lease: lease)
  }

  private func completePreparation(_ identity: Identity, result: Result<Runtime, Error>) {
    guard let preparation = preparations.removeValue(forKey: identity) else { return }
    if !preparation.waiters.isEmpty, case .success(let runtime) = result {
      loaded = runtime
      loadedIdentity = identity
    }
    for waiter in preparation.waiters.values { waiter.resume(with: result) }
  }

  private func prepareEngine(_ request: SpeechPreparation) async throws -> Runtime.Engine {
    try checkHardware(request.model)
    if request.model.isDiarizationModel,
      let provider = diarizationProviders[request.model.providerID]
    {
      return .diarization(try await provider.prepare(request))
    }
    if let provider = providers[request.model.providerID] {
      return .transcription(try await provider.prepare(request))
    }
    throw ModelStoreError.unknownModel
  }

  private func releaseWaiter(_ token: UUID) {
    for identity in Array(preparations.keys) {
      guard let waiter = preparations[identity]?.waiters.removeValue(forKey: token) else {
        continue
      }
      waiter.resume(throwing: CancellationError())
      if preparations[identity]?.waiters.isEmpty == true { preparations[identity]?.task.cancel() }
      return
    }
  }

  func cancelPreparation() {
    for identity in Array(preparations.keys) {
      guard let preparation = preparations[identity] else { continue }
      preparation.task.cancel()
      preparations[identity]?.waiters.removeAll()
      for waiter in preparation.waiters.values { waiter.resume(throwing: CancellationError()) }
    }
  }

  private func checkHardware(_ model: SpeechModelDescriptor) throws {
    #if !arch(arm64)
      if model.capabilities.requiresAppleSilicon {
        throw SpeechError.unavailable(
          String(localized: "This model requires an Apple Silicon Mac."))
      }
    #endif
  }
}
