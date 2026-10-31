import Foundation
import SilliesCore
import SilliesPersistence

/// Serial application boundary for persistence, paging, and bounded detail retention. No UI imports.
package actor VaultLibrary {
  package static let defaultCacheBytes = 8 * 1_024 * 1_024
  private let directory: URL
  private var database: VaultDatabase?
  private var cache: VaultBodyCache

  package init(directory: URL, cacheBytes: Int = defaultCacheBytes) {
    self.directory = directory
    cache = VaultBodyCache(capacity: cacheBytes)
  }

  private func storage() throws -> VaultDatabase {
    dispatchPrecondition(condition: .notOnQueue(.main))
    if let database { return database }
    let opened = try VaultDatabase(directory: directory)
    database = opened
    return opened
  }

  package func snapshot() throws -> VaultSnapshot {
    let database = try storage()
    return try VaultSnapshot(
      page: database.page(.init()), eligibleRetentionCount: database.eligibleRetentionCount())
  }
  package func page(_ request: VaultPageRequest) throws -> VaultPage {
    try Task.checkCancellation()
    return try storage().page(request)
  }
  package func matchingHeaders(_ ids: Set<UUID>, search: SessionRecordSearch) throws
    -> VaultHeaderMatches
  {
    try storage().matchingHeaders(ids, search: search)
  }
  package func record(id: UUID) throws -> SessionRecord? {
    try Task.checkCancellation()
    if let record = cache.record(id) { return record }
    let database = try storage()
    let precedingBytes = database.metrics.decodedBodyBytes
    guard let record = try database.record(id: id) else { return nil }
    cache.insert(record, cost: database.metrics.decodedBodyBytes - precedingBytes)
    return record
  }
  package func commit(_ mutation: VaultMutation) throws -> VaultSnapshot {
    let database = try storage()
    // A failed post-commit cleanup must not leave stale cached content visible.
    defer {
      for write in mutation.records { cache.remove(write.record.id) }
      switch mutation.deletion {
      case .all: cache.removeAll()
      case .records(let ids): for id in ids { cache.remove(id) }
      }
      if mutation.retention.limit != nil { cache.removeAll() }
    }
    let removed = try database.commit(mutation)
    let current = try snapshot()
    return .init(
      page: current.page, eligibleRetentionCount: current.eligibleRetentionCount,
      removedRecordIDs: removed)
  }
  package func pendingSummaryIDs() throws -> [UUID] { try storage().pendingSummaryIDs() }
  package func pendingScreenshot() throws -> SessionRecordHeader? {
    try storage().pendingScreenshot()
  }
  package func identifiers() throws -> [UUID] { try storage().identifiers() }
  package func metrics() throws -> VaultStorageMetrics { try storage().metrics }
  package var retainedBodyBytes: Int { cache.retainedBytes }

  package func export(_ selection: VaultExportSelection, to destination: URL) async throws -> Int {
    let ids: [UUID]
    switch selection {
    case .all: ids = try identifiers()
    case .records(let selected): ids = selected
    }
    let exporter = VaultMarkdownExporter(sourceDirectory: directory)
    var completed = 0
    for id in ids {
      try Task.checkCancellation()
      if let record = try storage().record(id: id) {
        _ = try exporter.export(record, to: destination)
        completed += 1
      }
      await Task.yield()
    }
    return completed
  }
}
