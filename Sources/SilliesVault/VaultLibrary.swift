import Foundation
import SilliesCore
import SilliesPersistence

/// Serial application boundary for persistence, paging, and bounded detail retention. No UI imports.
package actor VaultLibrary {
  package enum Opening { case existing, applicationLaunch }
  private enum StartupRecovery { case pending, completed }
  private var startupRecovery: StartupRecovery
  package private(set) var restoreReceipt: VaultPreparedRestore.Receipt?
  package static let defaultCacheBytes = 8 * 1_024 * 1_024
  let directory: URL
  private var database: VaultDatabase?
  var cache: VaultBodyCache
  let semanticSearches: VaultSemanticSearchWorker
  let workspaceReader: VaultWorkspaceReader
  let documentReader: VaultWorkspaceReader
  let assistantReader: VaultWorkspaceReader
  let workspaceExporter: VaultWorkspaceExportWorker
  let backupWorker: VaultBackupWorker
  let restoreWorker: VaultRestoreWorker
  var embeddings: SearchEmbeddingAccess?
  var indexTask: Task<Void, Never>?
  var indexGeneration = UUID()
  var searchRevision = UUID()
  var indexFailure: String?
  var contentTask: Task<Void, Never>?
  var contentGeneration = UUID()
  var contentFailure: String?
  var cleanupEnabled = false
  var cleanupTask: Task<Void, Never>?
  var cleanupGeneration = UUID()
  var cleanupFailure: String?

  package init(directory: URL, cacheBytes: Int = defaultCacheBytes, opening: Opening = .existing) {
    self.directory = directory
    startupRecovery = opening == .applicationLaunch ? .pending : .completed
    cache = VaultBodyCache(capacity: cacheBytes)
    semanticSearches = VaultSemanticSearchWorker(directory: directory)
    workspaceReader = VaultWorkspaceReader(directory: directory)
    documentReader = VaultWorkspaceReader(directory: directory)
    assistantReader = VaultWorkspaceReader(directory: directory)
    workspaceExporter = VaultWorkspaceExportWorker(directory: directory)
    backupWorker = VaultBackupWorker(source: directory)
    restoreWorker = VaultRestoreWorker(directory: directory)
  }

  func storage() throws -> VaultDatabase {
    dispatchPrecondition(condition: .notOnQueue(.main))
    if let database { return database }
    if startupRecovery == .pending {
      restoreReceipt = try VaultPreparedRestore(directory: directory).activate()
      startupRecovery = .completed
    }
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
  package func search(_ request: VaultSearchRequest) async throws -> [VaultSearchMatch] {
    try Task.checkCancellation()
    let revision = searchRevision
    _ = try storage()
    let candidates = request.rankingCandidates
    let keywords = try await assistantReader.search(candidates)
    let semantic = try await relatedMatches(candidates)
    guard revision == searchRevision else { return try await assistantReader.search(request) }
    return VaultRankFusion.merge(
      [keywords, semantic], identifiedBy: \.header.id, limit: request.limit)
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
    searchRevision = UUID()
    scheduleCleanup()
    scheduleIndex()
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
    _ = try storage()
    return try await workspaceExporter.export(selection, to: destination) { [self] id in
      try await prepareDocument(id: id)
    }
  }
  package nonisolated func backup(to destination: URL) async throws -> URL {
    try await backupWorker.write(to: destination)
  }
  package nonisolated func storageUsage() async throws -> VaultStorageUsage {
    try await backupWorker.usage()
  }
}
