import AppKit
import Foundation
import Observation
import SilliesCore
import SilliesPersistence

private struct WeakVaultBox {
  weak var store: SessionVaultStore?
}

/// Views read downsampled preview images from a byte-bounded memory cache; disk reads, PNG
/// encoding, preview downsampling, and decoding run on `ioQueue`.
@MainActor @Observable
final class SessionVaultStore {
  nonisolated static let maxStoredRecords = 200
  nonisolated static let maxCacheBytes = VaultImageCache.maximumBytes
  nonisolated static let maxPreviewPixelDimension = VaultImageCodec.maxPreviewPixelDimension
  private enum LoadState { case loading, ready, failed }
  private enum PreviewPreparation { case cached, worker }

  private(set) var records: [SessionRecord] = [] { didSet { searchRevision &+= 1 } }
  private(set) var searchRevision = 0
  @ObservationIgnored private lazy var searchIndex = VaultSearchService(directory: storageDirectory)
  @ObservationIgnored private var searchCleanup: Task<Void, Never>?
  @ObservationIgnored private let screenshotText = VaultOCRScheduler()
  private let defaults: UserDefaults
  private(set) var retentionPolicy: VaultRetentionPolicy

  func search(_ request: SessionRecordSearch) async throws -> Set<UUID> {
    try await searchIndex.search(request, records: records, revision: searchRevision)
  }
  private func discardSearchCache() {
    searchCleanup = Task.detached { [searchIndex, preceding = searchCleanup] in
      await preceding?.value
      do { try await searchIndex.discard() } catch {
        fputs("Could not clear the search cache: \(error)\n", stderr)
      }
    }
  }
  private var loadError: String?
  private var writeError: String?
  var persistenceError: String? { loadError ?? writeError }
  private(set) var pinnedRecordID: UUID?
  private let imageCache = VaultImageCache()
  var totalCachedImageBytes: Int { imageCache.totalBytes }
  @ObservationIgnored private var pendingImageLoads: Set<String> = []
  typealias NotesGenerator = VaultSummaryScheduler.Generator
  @ObservationIgnored private let summaries: VaultSummaryScheduler
  @ObservationIgnored private var loadState = LoadState.loading
  private var isLoading: Bool { loadState == .loading }
  private var needsSuccessfulLoad: Bool { loadState != .ready }
  var isReadyForRetention: Bool { loadState == .ready }
  @ObservationIgnored private var loadCompletions: [() -> Void] = []
  @ObservationIgnored private var persistencePending = false
  @ObservationIgnored private var removedWhileLoading: Set<UUID> = []
  @ObservationIgnored private var discardLoadedRecords = false
  @ObservationIgnored private let stagedPreviews = VaultPreviewBuffer()
  @ObservationIgnored private let clipboard: VaultClipboard
  let storageDirectory: URL
  private var repository: SessionRecordRepository {
    SessionRecordRepository(directory: storageDirectory)
  }
  private var files: VaultFileStorage { VaultFileStorage(directory: storageDirectory) }
  @ObservationIgnored nonisolated private static let ioQueue = DispatchQueue(
    label: "app.sillies.session-vault", qos: .utility)
  @ObservationIgnored private static var activeStoresByDirectory: [URL: WeakVaultBox] = [:]

  var pendingSummaryCount: Int {
    summaries.count
  }

  init(
    directory: URL? = nil, pasteboard: NSPasteboard = .general,
    defaults: UserDefaults = .standard,
    notesGenerator: @escaping NotesGenerator = { record in
      if record.kind == .stash {
        let (summary, actions) = await SessionSummaryWorker.summarize(
          text: record.primaryText, fallbackContext: record.summary)
        return LocalNotes(summary: summary, actions: actions)
      }
      return await LocalReasoningService.shared.notes(
        for: record.primaryText, kind: record.kind, fallback: record.summary,
        localeIdentifier: record.languageIdentifier)
    }
  ) {
    self.defaults = defaults
    retentionPolicy =
      VaultRetentionPolicy(rawValue: defaults.string(forKey: "vault.retention") ?? "") ?? .keepAll
    summaries = VaultSummaryScheduler(generate: notesGenerator)
    clipboard = VaultClipboard(pasteboard: pasteboard, queue: Self.ioQueue)
    if let directory {
      storageDirectory = directory
    } else {
      let appSupport =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory())
      storageDirectory = appSupport.appendingPathComponent("Sillies/Vault", isDirectory: true)
    }
    let directoryKey = storageDirectory.standardizedFileURL
    if let previousStore = Self.activeStoresByDirectory[directoryKey]?.store,
      previousStore !== self
    {
      previousStore.cancelPendingSummaries()
    }
    Self.activeStoresByDirectory[directoryKey] = WeakVaultBox(store: self)
    screenshotText.next = { [weak self] in
      guard let self,
        let record = self.records.first(where: { $0.screenshotTextState == .pending }),
        let url = self.imageURL(for: record)
      else { return nil }
      return .init(id: record.id, url: url)
    }
    screenshotText.complete = { [weak self] in self?.completeScreenshotText(id: $0, result: $1) }
    loadAsync()
  }

  func add(_ record: SessionRecord, image: CGImage? = nil, pngData: Data? = nil) {
    var updated = record
    if let image {
      let filename = "\(record.id.uuidString).png"
      updated.imageFilename = filename
      let needsDownsampling =
        max(image.width, image.height) > Self.maxPreviewPixelDimension
      if needsDownsampling {
        pendingImageLoads.insert(filename)
      } else {
        storeCachedImage(image, for: filename)
      }
      saveImageAsync(
        image, preencodedPNGData: pngData, filename: filename,
        preview: needsDownsampling ? .worker : .cached)
    }
    records.insert(updated, at: 0)
    trimHistory()
    persistAsync()
    scheduleSummaryRefinement(for: updated)
    whenPersisted { [weak self] error in if error == nil { self?.screenshotText.pump() } }
  }

  func update(_ record: SessionRecord) {
    guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
    records[index] = record
    persistAsync()
  }

  func updateTranscript(_ record: SessionRecord) {
    summaries.cancel(id: record.id)
    var updated = record
    updated.summaryPending = true
    update(updated)
    scheduleSummaryRefinement(for: updated)
  }

  func completePendingSummary(id: UUID, summary: String, actionItems: [String]) {
    summaries.cancel(id: id)
    guard let index = records.firstIndex(where: { $0.id == id }) else { return }
    var updated = records[index]
    updated.summary = summary
    updated.actionItems = actionItems
    updated.summaryPending = false
    records[index] = updated
    persistAsync()
  }

  func resumePendingSummaries() {
    summaries.resume()
    for record in records where record.summaryPending {
      scheduleSummaryRefinement(for: record)
    }
  }

  func flushPendingSummaries() async {
    await waitUntilLoaded()
    resumePendingSummaries()
    await summaries.flush()
    await flush()
  }

  func cancelPendingSummaries() { summaries.stop() }

  func suspendBackgroundProcessing() {
    summaries.stop()
    screenshotText.stop()
  }
  func resumeBackgroundProcessing() {
    resumePendingSummaries()
    screenshotText.resume()
  }

  func retryScreenshotText(_ record: SessionRecord) {
    var record = record
    record.screenshotTextState = .pending
    update(record)
    screenshotText.pump()
  }

  private func completeScreenshotText(id: UUID, result: Result<String, Error>) {
    guard var record = records.first(where: { $0.id == id }), record.screenshotTextState == .pending
    else { return }
    switch result {
    case .success(let text):
      record.extractedText = text
      record.screenshotTextState = .complete
      record.processingNote = text.isEmpty ? "No readable text was found in this screenshot." : ""
    case .failure(let error):
      record.screenshotTextState = .failed
      record.processingNote = "Screenshot text recognition failed: \(error.localizedDescription)"
      fputs("\(record.processingNote)\n", stderr)
    }
    update(record)
  }

  func applyRetention(_ policy: VaultRetentionPolicy) {
    guard isReadyForRetention else { return }
    retentionPolicy = policy
    defaults.set(policy.rawValue, forKey: "vault.retention")
    trimHistory()
    persistAsync()
  }

  func setPinnedRecord(_ id: UUID?) {
    pinnedRecordID = id
    imageCache.pinnedFilename = id.flatMap { selected in
      records.first { $0.id == selected }?.imageFilename
    }
    if let id, let record = records.first(where: { $0.id == id }) {
      prepareImage(for: record)
    }
  }

  func remove(id: UUID) {
    if needsSuccessfulLoad {
      removedWhileLoading.insert(id)
      persistencePending = true
    }
    summaries.cancel(id: id)
    if pinnedRecordID == id { setPinnedRecord(nil) }
    guard let index = records.firstIndex(where: { $0.id == id }) else { return }
    let removed = records.remove(at: index)
    if let file = removed.imageFilename {
      evictCachedImage(for: file)
      deleteAttachmentAsync(filename: file)
    }
    if let file = removed.audioFilename { deleteAttachmentAsync(filename: file) }
    discardSearchCache()
    persistAsync()
  }

  func clearAll() {
    if needsSuccessfulLoad { discardLoadedRecords = true }
    summaries.removeAll()
    pinnedRecordID = nil
    let files = records.flatMap { [$0.imageFilename, $0.audioFilename].compactMap { $0 } }
    records.removeAll()
    imageCache.removeAll()
    pendingImageLoads.removeAll()
    stagedPreviews.removeAll()
    for file in files { deleteAttachmentAsync(filename: file) }
    discardSearchCache()
    persistAsync()
  }

  func flush() async {
    await withCheckedContinuation { continuation in
      flushOnIOQueue {
        continuation.resume()
      }
    }
    drainStagedPreviews()
  }

  func flushOnIOQueue(completion: @escaping @Sendable () -> Void) {
    guard !isLoading else {
      loadCompletions.append { self.flushOnIOQueue(completion: completion) }
      return
    }
    Self.ioQueue.async { [searchCleanup] in
      dispatchPrecondition(condition: .notOnQueue(.main))
      Task.detached {
        await searchCleanup?.value
        MainRunLoopDelivery.perform { completion() }
      }
    }
  }

  /// Acknowledges image and JSON writes, including a load still in flight at Save.
  func whenPersisted(_ completion: @escaping @MainActor (String?) -> Void) {
    flushOnIOQueue { [weak self] in
      MainActor.assumeIsolated { completion(self?.persistenceError) }
    }
  }

  func drainStagedPreviewsForTermination() {
    drainStagedPreviews()
  }

  func imageURL(for record: SessionRecord) -> URL? {
    attachmentURL(for: record.imageFilename)
  }

  /// Non-blocking cache lookup for SwiftUI view rendering.
  func cachedImage(for record: SessionRecord) -> NSImage? {
    drainStagedPreviews()
    guard let filename = record.imageFilename else { return nil }
    return imageCache.image(named: filename)
  }

  /// Decodes a downsampled preview of the snapshot PNG on `ioQueue` if not already in memory.
  func prepareImage(for record: SessionRecord) {
    drainStagedPreviews()
    guard let filename = record.imageFilename,
      imageCache.image(named: filename) == nil,
      !pendingImageLoads.contains(filename),
      let url = imageURL(for: record)
    else { return }
    pendingImageLoads.insert(filename)
    let staged = stagedPreviews
    Self.ioQueue.async { [weak self] in
      if let decoded = VaultImageCodec.decodePreview(at: url) {
        staged.append(filename: filename, image: decoded)
      }
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.pendingImageLoads.remove(filename)
        self.drainStagedPreviews()
      }
    }
  }

  func copyText(_ text: String) { clipboard.copyText(text) }

  func copyImage(for record: SessionRecord) {
    let fallback = cachedImage(for: record)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    clipboard.copyImage(at: imageURL(for: record), fallback: fallback)
  }

  private func scheduleSummaryRefinement(for record: SessionRecord) {
    summaries.schedule(record) { [weak self] notes in
      guard let self,
        let index = self.records.firstIndex(where: { $0.id == record.id })
      else { return }
      var updated = self.records[index]
      updated.summary = notes.summary
      updated.actionItems = notes.actions
      updated.explanation = notes.explanation
      updated.processingNote = [updated.processingNote, notes.notice].filter { !$0.isEmpty }.joined(
        separator: "\n")
      updated.summaryPending = false
      self.update(updated)
    }
  }

  func audioURL(for record: SessionRecord) -> URL? {
    attachmentURL(for: record.audioFilename)
  }

  private func attachmentURL(for filename: String?) -> URL? {
    guard let filename else { return nil }
    do {
      return try files.attachmentURL(for: filename)
    } catch {
      fputs(
        "SessionVaultStore rejected attachment filename: \(error.localizedDescription)\n", stderr)
      return nil
    }
  }

  private func trimHistory() {
    let expired = retentionPolicy.expired(in: records)
    guard !expired.isEmpty else { return }
    for record in expired {
      summaries.cancel(id: record.id)
      if let filename = record.imageFilename {
        evictCachedImage(for: filename)
        deleteAttachmentAsync(filename: filename)
      }
      if let filename = record.audioFilename { deleteAttachmentAsync(filename: filename) }
    }
    let expiredIDs = Set(expired.map(\.id))
    records.removeAll { expiredIDs.contains($0.id) }
    if !expired.isEmpty { discardSearchCache() }
  }

  func retrySaving() {
    guard !isLoading else { return }
    if loadState == .failed {
      loadState = .loading
      loadAsync()
    } else {
      writeError = nil
      persistAsync()
    }
  }

  private func drainStagedPreviews() {
    let drained = stagedPreviews.drain()
    guard !drained.isEmpty else { return }
    for entry in drained {
      pendingImageLoads.remove(entry.filename)
      guard records.contains(where: { $0.imageFilename == entry.filename }) else { continue }
      storeCachedImage(entry.image, for: entry.filename)
    }
  }

  private func storeCachedImage(_ image: CGImage, for filename: String) {
    imageCache.store(image, named: filename)
  }

  private func evictCachedImage(for filename: String) {
    imageCache.remove(named: filename)
    pendingImageLoads.remove(filename)
    stagedPreviews.remove(filename: filename)
  }

  func waitUntilLoaded() async {
    guard isLoading else { return }
    await withCheckedContinuation { continuation in
      loadCompletions.append { continuation.resume() }
    }
  }

  private func loadAsync() {
    let repository = repository
    Self.ioQueue.async { [weak self] in
      dispatchPrecondition(condition: .notOnQueue(.main))
      do {
        let loaded = try repository.load()
        MainRunLoopDelivery.perform { [weak self] in self?.finishLoading(loaded) }
      } catch {
        let message =
          "Could not load saved sessions. Existing files have been preserved. \(error.localizedDescription)"
        fputs("Session vault load failed: \(error.localizedDescription)\n", stderr)
        MainRunLoopDelivery.perform { [weak self] in self?.failLoading(message) }
      }
    }
  }

  private func failLoading(_ message: String) {
    loadState = .failed
    loadError = message
    finishLoadCompletions()
  }

  private func finishLoadCompletions() {
    let completions = loadCompletions
    loadCompletions.removeAll()
    for completion in completions { completion() }
  }

  private func finishLoading(_ loaded: [SessionRecord]) {
    var currentIDs = Set(records.map(\.id))
    var merged = records
    for record in loaded {
      guard !currentIDs.contains(record.id) else { continue }
      if discardLoadedRecords || removedWhileLoading.contains(record.id) {
        if let filename = record.imageFilename { deleteAttachmentAsync(filename: filename) }
        if let filename = record.audioFilename { deleteAttachmentAsync(filename: filename) }
      } else {
        merged.append(record)
        currentIDs.insert(record.id)
      }
    }
    records = merged
    trimHistory()
    if records.count != merged.count { persistencePending = true }
    loadState = .ready
    loadError = nil
    removedWhileLoading.removeAll()
    discardLoadedRecords = false
    if persistencePending {
      persistencePending = false
      persistAsync()
    }
    for record in records { scheduleSummaryRefinement(for: record) }
    screenshotText.pump()
    finishLoadCompletions()
  }

  private func persistAsync() {
    guard !needsSuccessfulLoad else {
      persistencePending = true
      return
    }
    let snapshot = records
    let repository = repository
    Self.ioQueue.async { [weak self] in
      dispatchPrecondition(condition: .notOnQueue(.main))
      do {
        try repository.save(snapshot)
      } catch {
        let message = "Could not save session notes: \(error.localizedDescription)"
        fputs("\(message)\n", stderr)
        MainRunLoopDelivery.perform { [weak self] in self?.writeError = message }
      }
    }
  }

  private func saveImageAsync(
    _ cgImage: CGImage, preencodedPNGData: Data?, filename: String, preview: PreviewPreparation
  ) {
    let files = files
    let staged = stagedPreviews
    Self.ioQueue.async { [weak self] in
      dispatchPrecondition(condition: .notOnQueue(.main))
      if preview == .worker {
        let preview = VaultImageCodec.preparePreview(from: cgImage)
        staged.append(filename: filename, image: preview)
        Task { @MainActor [weak self] in
          self?.drainStagedPreviews()
        }
      }
      guard let data = preencodedPNGData ?? VaultImageCodec.encodePNGData(from: cgImage) else {
        let message = "Could not encode the snapshot image."
        fputs("\(message)\n", stderr)
        MainRunLoopDelivery.perform { [weak self] in self?.writeError = message }
        return
      }
      do {
        try files.write(data, named: filename)
      } catch {
        let message = "Could not save snapshot: \(error.localizedDescription)"
        fputs("\(message)\n", stderr)
        MainRunLoopDelivery.perform { [weak self] in self?.writeError = message }
      }
    }
  }

  private func deleteAttachmentAsync(filename: String) {
    let files = files
    Self.ioQueue.async {
      dispatchPrecondition(condition: .notOnQueue(.main))
      do {
        try files.removeAttachment(named: filename)
      } catch {
        fputs(
          "SessionVaultStore failed to remove attachment: \(error.localizedDescription)\n", stderr)
      }
    }
  }
}
