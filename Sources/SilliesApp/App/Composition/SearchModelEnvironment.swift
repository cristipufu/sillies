import Foundation
import SilliesCore
import SilliesInference
import SilliesModelStore
import SilliesSearchModels
import SilliesVault

/// Application owner for the selected search model, its installation lease and derived index.
actor SearchModelEnvironment {
  struct Runtime: Sendable {
    let inference: InferenceActivity
    let executable: URL
  }
  struct Selection: Sendable {
    let id: String
    let save: @MainActor @Sendable (String) -> Void
  }
  static let appleID = "apple"
  static let preferenceKey = "searchModelID"
  private static let appleReservationBytes: Int64 = 512 * 1024 * 1024
  let store: ModelStore
  private let conversations: ConversationLibrary
  private let vault: VaultLibrary
  private let inference: InferenceActivity
  private let executable: URL
  private let saveSelection: @MainActor @Sendable (String) -> Void
  private let memoryPressure = MemoryPressureMonitor()
  private var selected: String
  private var session: EmbeddingWorkerSession?
  private var lease: InstalledModelLease?
  private var preparation: Task<Void, Never>?
  private var generation = UUID()
  private var retiringRuntimes = 0
  private var active = false
  private var pressure = MemoryPressureMonitor.Pressure.normal
  private var failure: String?

  init(
    store: ModelStore, conversations: ConversationLibrary, vault: VaultLibrary,
    runtime: Runtime, selection: Selection
  ) {
    self.store = store
    self.conversations = conversations
    self.vault = vault
    inference = runtime.inference
    executable = runtime.executable
    selected = selection.id
    saveSelection = selection.save
  }
  func modelCatalog() throws -> SearchModelCatalog { try .bundled() }
  func selectedID() -> String { selected }

  func select(_ id: String) async throws {
    if id != Self.appleID {
      guard let manifest = try modelCatalog().manifests.first(where: { $0.modelID == id }),
        try await store.isInstalled(manifest)
      else { throw ModelStoreError.notInstalled }
    }
    let token = await release()
    defer { beginPreparation() }
    guard token == generation else { return }
    selected = id
    await saveSelection(id)
  }

  func remove(_ manifest: SearchModelManifest) async throws {
    if selected == manifest.modelID { try await select(Self.appleID) }
    try await store.remove(manifest)
  }
  func resume() async {
    guard !active else { return }
    active = true
    let token = generation
    await memoryPressure.start { [weak self] pressure in
      await self?.setPressure(pressure)
    }
    guard token == generation, active else { return }
    beginPreparation()
  }
  func stop() async {
    active = false
    pressure = .normal
    await memoryPressure.stop()
    guard !active else { return }
    await release()
    beginPreparation()
  }
  func rebuild() async throws {
    if session == nil {
      beginPreparation()
      return
    }
    try await conversations.rebuildMemoryIndex()
    try await vault.rebuildSearchIndex()
  }
  func status() async throws -> SearchIndexStatus {
    if let failure { return .failed(failure) }
    if preparation != nil { return .preparing }
    guard active, pressure == .normal else { return .paused }
    let (progress, failure) = try await conversations.memoryIndexStatus()
    if let failure { return .failed(failure) }
    let (vaultProgress, vaultFailure) = try await vault.searchIndexStatus()
    if let vaultFailure { return .failed(vaultFailure) }
    guard let progress, let vaultProgress else { return .preparing }
    return .indexed(
      .init(
        processed: progress.processed + vaultProgress.processed,
        searchable: progress.searchable + vaultProgress.searchable,
        total: progress.total + vaultProgress.total))
  }
  private func setPressure(_ pressure: MemoryPressureMonitor.Pressure) async {
    self.pressure = pressure
    if pressure == .constrained { await release() }
    beginPreparation()
  }
  private func beginPreparation() {
    guard active, retiringRuntimes == 0, session == nil, preparation == nil, pressure == .normal
    else { return }
    failure = nil
    let token = generation
    preparation = Task { await prepare(token) }
  }
  private func prepare(_ token: UUID) async {
    defer { if token == generation { preparation = nil } }
    do {
      let configuration: EmbeddingConfiguration
      let bytes: Int64
      if selected == Self.appleID {
        configuration = .init(provider: "apple", identity: "apple")
        bytes = Self.appleReservationBytes
      } else {
        guard let manifest = try modelCatalog().manifests.first(where: { $0.modelID == selected })
        else { throw ModelStoreError.notInstalled }
        let acquired = try await store.acquire(manifest)
        guard token == generation, !Task.isCancelled else {
          await acquired.close()
          return
        }
        lease = acquired
        configuration = .init(
          provider: manifest.model.providerID,
          identity: manifest.modelID + "/" + manifest.revision + "/mean-l2-v1",
          directory: acquired.directory)
        bytes = manifest.downloadBytes
      }
      let runtime = EmbeddingWorkerSession(
        configuration: configuration, executable: executable,
        modelBytes: bytes, activity: inference)
      session = runtime
      let access = try await runtime.access()
      try Task.checkCancellation()
      guard token == generation else { return }
      try await conversations.useSearchEmbeddings(access)
      try Task.checkCancellation()
      guard token == generation else { return }
      try await vault.useSearchEmbeddings(access)
    } catch is CancellationError { return } catch {
      guard token == generation else { return }
      failure = error.localizedDescription
      fputs("Search preparation failed: \(error)\n", stderr)
      let failed = session
      let acquired = lease
      session = nil
      lease = nil
      retiringRuntimes += 1
      defer { retiringRuntimes -= 1 }
      await detachIndexes()
      await failed?.stop()
      await acquired?.close()
    }
  }
  @discardableResult private func release() async -> UUID {
    retiringRuntimes += 1
    defer { retiringRuntimes -= 1 }
    generation = UUID()
    let token = generation
    let pending = preparation
    let previous = session
    let acquired = lease
    preparation = nil
    session = nil
    lease = nil
    pending?.cancel()
    await detachIndexes()
    await previous?.stop()
    await pending?.value
    await acquired?.close()
    return token
  }

  private func detachIndexes() async {
    do { try await conversations.useSearchEmbeddings(nil) } catch {
      fputs("Memory search shutdown failed: \(error)\n", stderr)
    }
    do { try await vault.useSearchEmbeddings(nil) } catch {
      fputs("Vault search shutdown failed: \(error)\n", stderr)
    }
  }
}

enum SearchIndexStatus: Sendable {
  case paused, preparing
  case indexed(SearchIndexProgress)
  case failed(String)
}
