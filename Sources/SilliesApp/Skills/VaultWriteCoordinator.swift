import CoreGraphics
import Foundation
import SilliesCore
import SilliesPersistence
import SilliesVault

/// Coalesces edits by record ID. One detached commit owns encoding and persistence at a time.
@MainActor final class VaultWriteCoordinator {
  struct Image: Sendable {
    let id = UUID()
    let source: CGImage
    let encoded: Data?
  }
  struct Request: Sendable {
    let writes: [UUID: VaultRecordWrite]
    let images: [String: Image]
    let deletion: VaultDeletion
    let retention: VaultRetentionPolicy
  }
  typealias Commit = @Sendable (Request) async throws -> VaultSnapshot
  private let commit: Commit
  private var pending: [UUID: VaultRecordWrite] = [:]
  private var images: [String: Image] = [:]
  private var deletion = VaultDeletion.records([])
  private var retention = VaultRetentionPolicy.keepAll
  private var active: Request?
  private var hasWork = false
  private var enabled = false
  private var scheduled = false
  private var failed = false
  private var waiters: [@MainActor @Sendable () -> Void] = []
  var report: (String?) -> Void = { _ in }
  var committed: (VaultSnapshot) -> Void = { _ in }
  private(set) var committedBatches = 0
  var pendingBatchCount: Int { (active == nil ? 0 : 1) + (hasWork ? 1 : 0) }

  init(library: VaultLibrary, commit: Commit? = nil) {
    self.commit =
      commit ?? { request in
        let attachments = try request.images.map { filename, image in
          guard let data = image.encoded ?? VaultImageCodec.encodePNGData(from: image.source) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
          }
          return VaultAttachment(filename: filename, data: data)
        }
        return try await library.commit(
          .init(
            records: Array(request.writes.values), deletion: request.deletion,
            retention: request.retention, attachments: attachments))
      }
  }

  func activate() {
    enabled = true
    schedule()
  }
  func stage(_ image: CGImage, encoded: Data?, filename: String) {
    images[filename] = Image(source: image, encoded: encoded)
  }
  func save(_ write: VaultRecordWrite) {
    let id = write.record.id
    var latest = write
    if case .insert = pending[id] ?? active?.writes[id] { latest = .insert(write.record) }
    pending[id] = latest
    if case .records(var ids) = deletion {
      ids.remove(id)
      deletion = .records(ids)
    }
    hasWork = true
    schedule()
  }
  func remove(_ id: UUID) {
    if let filename = pending.removeValue(forKey: id)?.record.imageFilename {
      images.removeValue(forKey: filename)
    }
    if case .records(var ids) = deletion {
      ids.insert(id)
      deletion = .records(ids)
    }
    hasWork = true
    schedule()
  }
  func clear() {
    pending.removeAll()
    images.removeAll()
    deletion = .all
    hasWork = true
    schedule()
  }
  func applyRetention(_ policy: VaultRetentionPolicy) {
    retention = policy
    hasWork = true
    schedule()
  }
  func record(_ id: UUID) -> SessionRecord? {
    if let record = pending[id]?.record { return record }
    guard !isRemoved(id) else { return nil }
    return active?.writes[id]?.record
  }
  func isRemoved(_ id: UUID) -> Bool {
    if pending[id] != nil { return false }
    if contains(id, in: deletion) { return true }
    guard let active, active.writes[id] == nil else { return false }
    return contains(id, in: active.deletion)
  }
  private func contains(_ id: UUID, in deletion: VaultDeletion) -> Bool {
    switch deletion {
    case .all: return true
    case .records(let ids): return ids.contains(id)
    }
  }
  var pendingHeaders: [SessionRecordHeader] {
    var writes = active?.writes ?? [:]
    for (id, write) in pending { writes[id] = write }
    return writes.values.filter { !isRemoved($0.record.id) }.map { SessionRecordHeader($0.record) }
  }
  func retry() {
    failed = false
    startNext()
  }
  func flush(_ completion: @escaping @MainActor @Sendable () -> Void) {
    waiters.append(completion)
    startNext()
  }
  private func schedule() {
    guard enabled, active == nil, !scheduled, !failed else { return }
    scheduled = true
    MainRunLoopDelivery.perform { [weak self] in
      self?.scheduled = false
      self?.startNext()
    }
  }
  private func startNext() {
    guard active == nil else { return }
    guard enabled, !failed, hasWork else {
      finishWaiters()
      return
    }
    let referenced = Set(pending.values.compactMap { $0.record.imageFilename })
    let request = Request(
      writes: pending, images: images.filter { referenced.contains($0.key) }, deletion: deletion,
      retention: retention)
    pending.removeAll()
    deletion = .records([])
    hasWork = false
    active = request
    Task.detached { [weak self, commit] in
      let result: Result<VaultSnapshot, Error>
      do { result = .success(try await commit(request)) } catch { result = .failure(error) }
      MainRunLoopDelivery.perform { self?.complete(request, result: result) }
    }
  }
  private func complete(_ request: Request, result: Result<VaultSnapshot, Error>) {
    active = nil
    switch result {
    case .success(let snapshot):
      committedBatches += 1
      for (filename, image) in request.images where images[filename]?.id == image.id {
        images.removeValue(forKey: filename)
      }
      report(nil)
      committed(snapshot)
    case .failure(let error):
      failed = true
      restore(request)
      let message = "Could not save the complete capture: \(error.localizedDescription)"
      fputs("\(message)\n", stderr)
      report(message)
    }
    startNext()
  }
  private func restore(_ request: Request) {
    if case .all = deletion { return }
    for (id, write) in request.writes where !isRemoved(id) {
      if let newer = pending[id] {
        if case .insert = write { pending[id] = .insert(newer.record) }
      } else {
        pending[id] = write
      }
    }
    if case .records(let ids) = deletion {
      switch request.deletion {
      case .all: deletion = .all
      case .records(let prior): deletion = .records(ids.union(prior).subtracting(pending.keys))
      }
    }
    hasWork = true
  }
  private func finishWaiters() {
    let waiting = waiters
    waiters.removeAll()
    for completion in waiting { completion() }
  }
}
