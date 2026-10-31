import AppKit
import Foundation
import Observation
import SilliesCore
import SilliesPersistence
import SilliesReasoning
import SilliesVault

/// Native adapter for a paged Vault. Only recent headers and pending unsaved captures live here.
@MainActor @Observable final class SessionVaultStore {
  nonisolated static let maxCacheBytes = VaultImageCache.maximumBytes
  nonisolated static let maxPreviewPixelDimension = VaultImageCodec.maxPreviewPixelDimension
  private enum LoadState { case loading, ready, failed }
  private(set) var records: [SessionRecordHeader] = []
  private(set) var recordCount = 0
  private(set) var eligibleRetentionCount = 0
  private(set) var changes = VaultChangeJournal()
  var searchRevision: Int { changes.version }
  private(set) var retentionPolicy: VaultRetentionPolicy
  private(set) var pinnedRecordID: UUID?
  private(set) var persistenceError: String?
  private(set) var isLoading = true
  @ObservationIgnored private var loadState = LoadState.loading
  @ObservationIgnored private var loadCompletions: [@MainActor () -> Void] = []
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let writer: VaultWriteCoordinator
  @ObservationIgnored private lazy var editor = makeEditor()
  @ObservationIgnored private let media: VaultMediaStore
  @ObservationIgnored private let summaries: VaultSummaryScheduler
  @ObservationIgnored private let screenshotText = VaultOCRScheduler()
  @ObservationIgnored private var notesLoading: Task<Void, Never>?
  @ObservationIgnored private var notesGeneration = UUID()
  @ObservationIgnored private var backgroundEnabled = true
  let library: VaultLibrary
  let storageDirectory: URL
  typealias NotesGenerator = VaultSummaryScheduler.Generator
  nonisolated private static let imageQueue = DispatchQueue(
    label: "app.sillies.vault-images", qos: .utility)
  var totalCachedImageBytes: Int { media.cachedBytes }
  var pendingSummaryCount: Int { summaries.count }
  var isReadyForRetention: Bool { loadState == .ready }

  init(
    directory: URL? = nil, pasteboard: NSPasteboard = .general, defaults: UserDefaults = .standard,
    notesGenerator: @escaping NotesGenerator
  ) {
    self.defaults = defaults
    retentionPolicy =
      VaultRetentionPolicy(rawValue: defaults.string(forKey: "vault.retention") ?? "") ?? .keepAll
    storageDirectory =
      directory
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Sillies/Vault", isDirectory: true)
    let library = VaultLibrary(directory: storageDirectory)
    self.library = library
    writer = VaultWriteCoordinator(library: library)
    media = VaultMediaStore(
      directory: storageDirectory, pasteboard: pasteboard, queue: Self.imageQueue)
    summaries = VaultSummaryScheduler(
      load: { try await library.record(id: $0) }, generate: notesGenerator)
    writer.report = { [weak self] in self?.persistenceError = $0 }
    writer.committed = { [weak self] in self?.receive($0) }
    screenshotText.next = { [weak self, library] in
      guard let header = try await library.pendingScreenshot(),
        let url = self?.media.url(header.imageFilename)
      else { return nil }
      return .init(id: header.id, url: url, revision: header.screenshotRevision)
    }
    screenshotText.complete = { [weak self] in
      await self?.completeScreenshotText(request: $0, result: $1)
    }
    load()
  }

  private func makeEditor() -> VaultRecordEditor {
    let library = library
    return VaultRecordEditor(
      load: { id in try await library.record(id: id) },
      context: .init(
        revision: { [weak self] in self?.changes.revision(for: $0) ?? Int.max },
        pending: { [weak self] in self?.writer.record($0) },
        isRemoved: { [weak self] in self?.writer.isRemoved($0) ?? true },
        save: { [weak self] in
          self?.writer.save(.update($0))
          self?.present($0)
        }))
  }

  func page(_ request: VaultPageRequest) async throws -> VaultPage {
    await flush()
    if let persistenceError { throw VaultStorageError(message: persistenceError) }
    return try await library.page(request)
  }
  func matchingHeaders(_ ids: Set<UUID>, search: SessionRecordSearch) async throws
    -> VaultHeaderMatches
  {
    await flush()
    if let persistenceError { throw VaultStorageError(message: persistenceError) }
    return try await library.matchingHeaders(ids, search: search)
  }
  func record(id: UUID) async throws -> SessionRecord? {
    await waitUntilLoaded()
    while true {
      try Task.checkCancellation()
      let revision = changes.revision(for: id)
      if let record = writer.record(id) { return record }
      guard !writer.isRemoved(id) else { return nil }
      let loaded = try await library.record(id: id)
      guard changes.revision(for: id) == revision else { continue }
      guard !writer.isRemoved(id) else { return nil }
      return writer.record(id) ?? loaded
    }
  }
  @discardableResult func edit(id: UUID, _ command: VaultRecordEdit) async throws -> Bool {
    try Task.checkCancellation()
    return try await withCheckedThrowingContinuation { continuation in
      submitEdit(id: id, command) { continuation.resume(with: $0) }
    }
  }
  func submitEdit(
    id: UUID, _ command: VaultRecordEdit, completion: @escaping VaultRecordEditor.Completion
  ) {
    if command.requestsNotes { summaries.cancel(id: id) }
    editor.submit(id: id, edit: command) { [weak self] result in
      if case .success(true) = result, command.requestsNotes || command.requestsScreenshot {
        self?.scheduleProcessing(id: id, notesPending: command.requestsNotes)
      }
      completion(result)
    }
  }
  func add(_ record: SessionRecord, image: CGImage? = nil, pngData: Data? = nil) {
    var updated = record
    if let image {
      let filename = "\(record.id.uuidString).png"
      updated.imageFilename = filename
      writer.stage(image, encoded: pngData, filename: filename)
      media.stage(image, filename: filename)
    }
    if !records.contains(where: { $0.id == updated.id }) { recordCount += 1 }
    writer.save(.insert(updated))
    present(updated)
    scheduleProcessing(id: updated.id, notesPending: updated.summaryPending)
  }
  func applyRetention(_ policy: VaultRetentionPolicy) {
    guard isReadyForRetention else { return }
    retentionPolicy = policy
    defaults.set(policy.rawValue, forKey: "vault.retention")
    writer.applyRetention(policy)
  }
  func remove(id: UUID) {
    summaries.cancel(id: id)
    if pinnedRecordID == id { setPinnedRecord(nil) }
    if let header = records.first(where: { $0.id == id }) { media.remove(header.imageFilename) }
    records.removeAll { $0.id == id }
    recordCount = max(0, recordCount - 1)
    writer.remove(id)
    changes.record([id])
  }
  func clearAll() {
    summaries.removeAll()
    records.removeAll()
    recordCount = 0
    eligibleRetentionCount = 0
    pinnedRecordID = nil
    media.clear()
    writer.clear()
    changes.reset()
  }
  func retrySaving() {
    guard !isLoading else { return }
    if loadState == .failed {
      loadState = .loading
      isLoading = true
      load()
    } else {
      writer.retry()
    }
  }

  private func present(_ record: SessionRecord) {
    let header = SessionRecordHeader(record)
    records.removeAll { $0.id == record.id }
    records.insert(header, at: 0)
    records = Array(
      records.sorted { $0.createdAt > $1.createdAt }.prefix(VaultPageRequest.maximumPageSize))
    changes.record([record.id])
  }
  private func receive(_ snapshot: VaultSnapshot) {
    let pending = writer.pendingHeaders
    let pendingIDs = Set(pending.map(\.id))
    records = Array(
      (pending
        + snapshot.page.records.filter { !pendingIDs.contains($0.id) && !writer.isRemoved($0.id) })
        .sorted { $0.createdAt > $1.createdAt }.prefix(VaultPageRequest.maximumPageSize))
    recordCount = snapshot.page.total
    eligibleRetentionCount = snapshot.eligibleRetentionCount
    changes.record(snapshot.removedRecordIDs)
  }
  private func load() {
    Task.detached { [weak self, library] in
      let result: Result<VaultSnapshot, Error>
      do { result = .success(try await library.snapshot()) } catch { result = .failure(error) }
      MainRunLoopDelivery.perform { self?.finishLoading(result) }
    }
  }
  private func finishLoading(_ result: Result<VaultSnapshot, Error>) {
    isLoading = false
    switch result {
    case .success(let snapshot):
      loadState = .ready
      persistenceError = nil
      receive(snapshot)
      changes.reset()
      if retentionPolicy.limit != nil { writer.applyRetention(retentionPolicy) }
      writer.activate()
      resumePendingSummaries()
      screenshotText.pump()
    case .failure(let error):
      loadState = .failed
      persistenceError =
        "Could not open the Vault. Existing files were preserved. \(error.localizedDescription)"
      fputs("Vault open failed: \(error)\n", stderr)
    }
    let completions = loadCompletions
    loadCompletions.removeAll()
    for completion in completions { completion() }
  }
  func waitUntilLoaded() async {
    guard isLoading else { return }
    await withCheckedContinuation { continuation in loadCompletions.append { continuation.resume() }
    }
  }
  func flush() async {
    await withCheckedContinuation { continuation in flushOnIOQueue { continuation.resume() } }
    media.drain()
  }
  func flushOnIOQueue(completion: @escaping @Sendable () -> Void) {
    guard !isLoading else {
      loadCompletions.append { self.flushOnIOQueue(completion: completion) }
      return
    }
    editor.flush { [writer] in
      writer.flush {
        Self.imageQueue.async { MainRunLoopDelivery.perform { completion() } }
      }
    }
  }
  func whenPersisted(_ completion: @escaping @MainActor (String?) -> Void) {
    flushOnIOQueue { [weak self] in MainActor.assumeIsolated { completion(self?.persistenceError) }
    }
  }
  func drainStagedPreviewsForTermination() { media.drain() }

  private func scheduleProcessing(id: UUID, notesPending: Bool) {
    whenPersisted { [weak self] error in
      guard let self, error == nil, self.backgroundEnabled else { return }
      if notesPending { self.scheduleSummary(id) }
      self.screenshotText.pump()
    }
  }
  private func scheduleSummary(_ id: UUID) {
    summaries.schedule(id) { [weak self] notes, revision in
      do {
        try await self?.edit(id: id, .completeNotes(notes, revision: revision))
        await self?.flush()
      } catch { fputs("Could not update Vault notes: \(error)\n", stderr) }
    }
  }
  func resumePendingSummaries() {
    guard backgroundEnabled, loadState == .ready, notesLoading == nil else { return }
    summaries.resume()
    let generation = UUID()
    notesGeneration = generation
    notesLoading = Task { [weak self, library] in
      do {
        let ids = try await library.pendingSummaryIDs()
        guard !Task.isCancelled, let self else { return }
        for id in ids { self.scheduleSummary(id) }
      } catch { fputs("Could not resume Vault notes: \(error)\n", stderr) }
      if self?.notesGeneration == generation { self?.notesLoading = nil }
    }
  }
  func flushPendingSummaries() async {
    await flush()
    resumePendingSummaries()
    await notesLoading?.value
    await summaries.flush()
    await flush()
  }
  func cancelPendingSummaries() {
    notesGeneration = UUID()
    notesLoading?.cancel()
    notesLoading = nil
    summaries.stop()
  }
  func suspendBackgroundProcessing() {
    backgroundEnabled = false
    cancelPendingSummaries()
    screenshotText.stop()
  }
  func resumeBackgroundProcessing() {
    backgroundEnabled = true
    resumePendingSummaries()
    screenshotText.resume()
  }
  private func completeScreenshotText(
    request: VaultOCRScheduler.Request, result: Result<String, Error>
  ) async {
    let command: VaultRecordEdit
    switch result {
    case .success(let text): command = .completeScreenshot(text: text, revision: request.revision)
    case .failure(let error):
      let message = "Screenshot text recognition failed: \(error.localizedDescription)"
      fputs("\(message)\n", stderr)
      command = .failScreenshot(message: message, revision: request.revision)
    }
    do {
      try await edit(id: request.id, command)
      await flush()
    } catch { fputs("Could not update screenshot text: \(error)\n", stderr) }
  }

  func setPinnedRecord(_ id: UUID?) {
    pinnedRecordID = id
    media.pin(records.first { $0.id == id }?.imageFilename)
  }
  func pin(_ record: SessionRecord) {
    pinnedRecordID = record.id
    media.pin(record.imageFilename)
  }
  func imageURL(for record: some SessionAttachmentReference) -> URL? {
    media.url(record.imageFilename)
  }
  func audioURL(for record: some SessionAttachmentReference) -> URL? {
    media.url(record.audioFilename)
  }
  func cachedImage(for record: some SessionAttachmentReference) -> NSImage? {
    media.image(record.imageFilename)
  }
  func prepareImage(for record: some SessionAttachmentReference) {
    media.prepare(record.imageFilename)
  }
  func copyImage(for record: some SessionAttachmentReference) {
    media.copyImage(record.imageFilename)
  }
  func copyText(_ text: String) { media.copyText(text) }
}
