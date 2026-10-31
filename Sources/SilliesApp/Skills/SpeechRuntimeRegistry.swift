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
  private struct Identity: Equatable {
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
    let identity: Identity
    let task: Task<Runtime, Error>
    var waiters: Set<UUID>
  }
  private var preparation: Preparation?

  init(
    store: ModelStore, providers: [any SpeechProvider],
    diarizationProviders: [any DiarizationProvider] = []
  ) throws {
    guard Set(providers.map(\.id)).count == providers.count,
      Set(diarizationProviders.map(\.id)).count == diarizationProviders.count
    else {
      throw SpeechError.unavailable("Duplicate speech or speaker provider registration.")
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
    guard preparation == nil, !validating else { throw ModelStoreError.busy }
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
    let task = try startPreparation(manifest, waiter: token)
    return try await withTaskCancellationHandler {
      defer { releaseWaiter(token) }
      let runtime = try await task.value
      try Task.checkCancellation()
      return runtime
    } onCancel: {
      Task { await self.releaseWaiter(token) }
    }
  }

  private func startPreparation(_ manifest: SpeechModelManifest?, waiter: UUID) throws -> Task<
    Runtime, Error
  > {
    let identity = Identity(manifest?.model ?? .apple)
    // Native speech must remain usable while a downloaded model specializes.
    if preparation != nil || validating, preparation?.identity != identity, manifest == nil {
      guard let provider = providers[SpeechModelDescriptor.apple.providerID] else {
        throw ModelStoreError.unknownModel
      }
      return Task(priority: .utility) {
        Runtime(model: try await provider.prepare(.init(model: .apple, directory: nil)), lease: nil)
      }
    }
    guard !validating else { throw ModelStoreError.busy }
    if var preparation {
      guard preparation.identity == identity else { throw ModelStoreError.busy }
      preparation.waiters.insert(waiter)
      self.preparation = preparation
      return preparation.task
    }
    let store = store
    let task = Task(priority: .utility) {
      defer { preparation = nil }
      let lease: InstalledModelLease?
      let descriptor: SpeechModelDescriptor
      if let manifest {
        descriptor = manifest.model
        lease = try await store.acquire(manifest)
      } else {
        descriptor = .apple
        lease = nil
      }
      let request = SpeechPreparation(model: descriptor, directory: lease?.directory)
      let engine = try await prepareEngine(request)
      try Task.checkCancellation()
      let runtime = Runtime(engine: engine, lease: lease)
      loaded = runtime
      loadedIdentity = identity
      return runtime
    }
    preparation = Preparation(identity: identity, task: task, waiters: [waiter])
    return task
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
    guard preparation?.waiters.remove(token) != nil else { return }
    if preparation?.waiters.isEmpty == true { preparation?.task.cancel() }
  }

  func cancelPreparation() { preparation?.task.cancel() }

  private func checkHardware(_ model: SpeechModelDescriptor) throws {
    #if !arch(arm64)
      if model.capabilities.requiresAppleSilicon {
        throw SpeechError.unavailable("This model requires an Apple Silicon Mac.")
      }
    #endif
  }
}
