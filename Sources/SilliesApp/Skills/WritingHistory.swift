import Foundation
import Observation
import SilliesCore
import SilliesPersistence
import SilliesWriting

/// One active write and the latest pending revision; failures retain unsaved recovery text.
@MainActor @Observable
final class WritingHistory: WritingHistoryRecording {
  static let maximumResults = 20
  private enum LoadState { case unavailable, loading, ready }
  private(set) var results: [WritingResult] = []
  private(set) var persistence = WritingHistoryPersistence.loading
  var error: String? { persistence.failure?.message }
  @ObservationIgnored var onPersistenceChange: (() -> Void)?
  private let repository: WritingHistoryRepository
  private let queue = DispatchQueue(label: "app.sillies.dictation-history", qos: .utility)
  private var loadState = LoadState.unavailable
  private var isWriting = false
  private var removed: Set<UUID> = []
  private var discardsLoaded = false
  private var revision = 0
  private var savedRevision = 0
  private var loadWaiters: [CheckedContinuation<Void, Never>] = []
  private var flushWaiters: [@MainActor @Sendable (Result<Void, WritingHistoryFailure>) -> Void] =
    []

  init(directory: URL) {
    repository = .init(directory: directory)
    startLoading()
  }

  func load() async {
    guard loadState != .ready else { return }
    startLoading()
    await withCheckedContinuation { loadWaiters.append($0) }
  }

  func retry() {
    if loadState == .ready { startWriting() } else { startLoading() }
  }

  private func startLoading() {
    guard loadState == .unavailable else { return }
    loadState = .loading
    setPersistence(.loading)
    queue.async { [weak self, repository] in
      let result = Result { try repository.load() }
      MainRunLoopDelivery.perform { self?.finishLoading(result) }
    }
  }

  private func finishLoading(_ result: Result<[WritingResult], Error>) {
    switch result {
    case .success(let stored):
      merge(stored)
      loadState = .ready
      if revision > savedRevision { startWriting() } else { setPersistence(.saved) }
    case .failure(let error):
      loadState = .unavailable
      report(.load(error.localizedDescription), diagnostic: error)
    }
    let pending = loadWaiters
    loadWaiters.removeAll()
    for waiter in pending { waiter.resume() }
    completeFlushIfSettled()
  }

  private func merge(_ stored: [WritingResult]) {
    let currentIDs = Set(results.map(\.id))
    if !discardsLoaded {
      results += stored.filter { !currentIDs.contains($0.id) && !removed.contains($0.id) }
    }
    results = Array(results.sorted { $0.createdAt > $1.createdAt }.prefix(Self.maximumResults))
    removed.removeAll()
    discardsLoaded = false
    if stored.count > Self.maximumResults { revision += 1 }
  }

  func save(_ result: WritingResult) {
    results.removeAll { $0.id == result.id }
    results.insert(result, at: 0)
    results = Array(results.prefix(Self.maximumResults))
    changed()
  }
  func remove(_ id: UUID) {
    if loadState != .ready { removed.insert(id) }
    results.removeAll { $0.id == id }
    changed()
  }
  func clear() {
    if loadState != .ready { discardsLoaded = true }
    results.removeAll()
    changed()
  }

  func flush(
    completion: @escaping @MainActor @Sendable (Result<Void, WritingHistoryFailure>) -> Void
  ) {
    flushWaiters.append(completion)
    completeFlushIfSettled()
  }
  @discardableResult func flush() async -> Result<Void, WritingHistoryFailure> {
    await withCheckedContinuation { continuation in flush { continuation.resume(returning: $0) } }
  }

  private func changed() {
    revision += 1
    startWriting()
  }
  private func startWriting() {
    guard loadState == .ready, !isWriting, revision > savedRevision else { return }
    isWriting = true
    setPersistence(.saving)
    let snapshot = results
    let version = revision
    queue.async { [weak self, repository] in
      let result = Result { try repository.save(snapshot) }
      MainRunLoopDelivery.perform { self?.finishWriting(result, version: version) }
    }
  }
  private func finishWriting(_ result: Result<Void, Error>, version: Int) {
    isWriting = false
    switch result {
    case .success:
      savedRevision = version
      if revision > savedRevision { startWriting() } else { setPersistence(.saved) }
    case .failure(let error): report(.save(error.localizedDescription), diagnostic: error)
    }
    completeFlushIfSettled()
  }
  private func completeFlushIfSettled() {
    let result: Result<Void, WritingHistoryFailure>
    switch persistence {
    case .loading, .saving: return
    case .saved: result = .success(())
    case .failed(let failure): result = .failure(failure)
    }
    let completions = flushWaiters
    flushWaiters.removeAll()
    for completion in completions { completion(result) }
  }
  private func setPersistence(_ value: WritingHistoryPersistence) {
    guard persistence != value else { return }
    persistence = value
    onPersistenceChange?()
  }
  private func report(_ failure: WritingHistoryFailure, diagnostic: Error) {
    fputs("Writing history: \(diagnostic)\n", stderr)
    setPersistence(.failed(failure))
  }
}
