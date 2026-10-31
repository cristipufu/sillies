import Foundation
import Observation
import SilliesModelStore

@MainActor @Observable
final class TextModelsPresentation {
  static let systemModelID = TextModelEnvironment.appleID
  private(set) var manifests: [TextModelManifest] = []
  private(set) var selectedModelID = TextModelEnvironment.appleID
  private(set) var states: [String: ModelInstallationState] = [:]
  private(set) var error: String?
  private(set) var isLoading = false
  @ObservationIgnored private let environment: TextModelEnvironment
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var loading: Task<Void, Never>?
  private(set) var activeID: String?

  init(environment: TextModelEnvironment) { self.environment = environment }

  func start() {
    guard loading == nil else { return }
    loading = Task { await load() }
  }
  func load() async {
    guard manifests.isEmpty, !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      manifests = try await environment.modelCatalog().manifests
      selectedModelID = await environment.selectedID()
      for manifest in manifests {
        states[manifest.modelID] =
          try await environment.store.isInstalled(manifest) ? .downloaded : .absent
      }
    } catch { report(error) }
  }

  func state(for id: String) -> ModelInstallationState { states[id] ?? .absent }
  func supports(_ manifest: TextModelManifest) -> Bool {
    ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024) >= manifest.model.minimumMemoryGB
  }

  func download(_ manifest: TextModelManifest) {
    guard operation == nil else { return }
    activeID = manifest.modelID
    states[manifest.modelID] = .downloading(0)
    error = nil
    operation = Task { [weak self, environment] in
      let (stream, continuation) = AsyncStream<ModelInstallationProgress>.makeStream(
        bufferingPolicy: .bufferingNewest(1))
      let delivery = Task { [weak self] in
        for await progress in stream {
          guard !Task.isCancelled else { return }
          let fraction = min(
            1, max(0, Double(progress.completedBytes) / Double(max(1, progress.totalBytes))))
          self?.states[manifest.modelID] =
            progress.phase == .verifying ? .verifying(fraction) : .downloading(fraction)
        }
      }
      do {
        try await environment.store.install(manifest) { continuation.yield($0) }
        continuation.finish()
        await delivery.value
        self?.states[manifest.modelID] = .downloaded
      } catch {
        continuation.finish()
        delivery.cancel()
        await delivery.value
        if Task.isCancelled {
          self?.states[manifest.modelID] = .paused
        } else {
          self?.states[manifest.modelID] = .failed(error.localizedDescription)
          self?.report(error)
        }
      }
      self?.finishOperation()
    }
  }

  func select(_ id: String) {
    perform(id) { [environment] in try await environment.select(id) }
  }
  func remove(_ manifest: TextModelManifest) {
    perform(manifest.modelID) { [environment] in try await environment.remove(manifest) }
  }
  func pauseDownload() {
    guard let activeID else { return }
    states[activeID] = .cancelling
    operation?.cancel()
  }
  func stop() {
    loading?.cancel()
    loading = nil
    operation?.cancel()
    Task.detached(priority: .utility) { [environment] in await environment.stop() }
  }

  private func perform(_ id: String, action: @escaping @Sendable () async throws -> Void) {
    guard operation == nil else { return }
    activeID = id
    error = nil
    operation = Task { [weak self, environment] in
      do {
        try await action()
        self?.selectedModelID = await environment.selectedID()
        if let manifest = self?.manifests.first(where: { $0.modelID == id }) {
          self?.states[id] =
            try await environment.store.isInstalled(manifest) ? .downloaded : .absent
        }
      } catch { self?.report(error) }
      self?.finishOperation()
    }
  }
  private func finishOperation() {
    operation = nil
    activeID = nil
  }
  private func report(_ error: Error) {
    self.error = error.localizedDescription
    fputs("Text models: \(error.localizedDescription)\n", stderr)
  }
}
