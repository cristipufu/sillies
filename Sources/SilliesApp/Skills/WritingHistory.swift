import Foundation
import Observation
import SilliesCore
import SilliesPersistence

/// Failed loads never authorize overwriting the separate, bounded recovery journal.
@MainActor @Observable
final class WritingHistory {
  static let maximumResults = 20
  private(set) var results: [WritingResult] = []
  private(set) var error: String?
  private let repository: WritingHistoryRepository
  private let queue = DispatchQueue(label: "app.sillies.dictation-history", qos: .utility)
  private var loaded = false
  private var loading = false
  private var removed: Set<UUID> = []
  private var discardsLoaded = false
  private var revision = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var loadCompletions: [@MainActor @Sendable () -> Void] = []

  init(directory: URL) {
    repository = .init(directory: directory)
    startLoading()
  }

  func load() async {
    guard !loaded else { return }
    startLoading()
    await withCheckedContinuation { waiters.append($0) }
  }

  private func startLoading() {
    guard !loading, !loaded else { return }
    loading = true
    queue.async { [weak self, repository] in
      let result = Result { try repository.load() }
      MainRunLoopDelivery.perform { self?.finishLoading(result) }
    }
  }

  private func finishLoading(_ result: Result<[WritingResult], Error>) {
    loading = false
    switch result {
    case .success(let stored):
      let currentIDs = Set(results.map(\.id))
      if !discardsLoaded {
        results += stored.filter { !currentIDs.contains($0.id) && !removed.contains($0.id) }
      }
      results = Array(results.sorted { $0.createdAt > $1.createdAt }.prefix(Self.maximumResults))
      loaded = true
      removed.removeAll()
      discardsLoaded = false
      error = nil
      if revision > 0 || stored.count > Self.maximumResults { persist() }
    case .failure(let failure): report(failure)
    }
    let pending = waiters
    waiters.removeAll()
    for waiter in pending { waiter.resume() }
    let completions = loadCompletions
    loadCompletions.removeAll()
    for completion in completions { flush(completion: completion) }
  }

  func save(_ result: WritingResult) {
    results.removeAll { $0.id == result.id }
    results.insert(result, at: 0)
    results = Array(results.prefix(Self.maximumResults))
    persist()
  }
  func remove(_ id: UUID) {
    if !loaded { removed.insert(id) }
    results.removeAll { $0.id == id }
    persist()
  }
  func clear() {
    if !loaded { discardsLoaded = true }
    results.removeAll()
    persist()
  }

  func flush(completion: @escaping @MainActor @Sendable () -> Void) {
    if loading {
      loadCompletions.append(completion)
      return
    }
    queue.async { MainRunLoopDelivery.perform(completion) }
  }
  func flush() async {
    await withCheckedContinuation { continuation in flush { continuation.resume() } }
  }

  private func persist() {
    revision += 1
    guard loaded else { return }
    let snapshot = results
    let version = revision
    queue.async { [weak self, repository] in
      let result = Result { try repository.save(snapshot) }
      MainRunLoopDelivery.perform {
        guard let self, self.revision == version else { return }
        switch result {
        case .success: self.error = nil
        case .failure(let failure): self.report(failure)
        }
      }
    }
  }
  private func report(_ error: Error) {
    self.error = "Recovery history could not be saved or loaded: \(error.localizedDescription)"
    fputs("Writing history: \(error)\n", stderr)
  }
}
