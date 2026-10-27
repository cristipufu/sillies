import AppKit
import Foundation
import ImageIO
import Observation
import SilliesCore

private final class StagedPreviewBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [(filename: String, image: CGImage)] = []

  func append(filename: String, image: CGImage) {
    lock.lock()
    entries.append((filename, image))
    lock.unlock()
  }

  func remove(filename: String) {
    lock.lock()
    entries.removeAll { $0.filename == filename }
    lock.unlock()
  }

  func removeAll() {
    lock.lock()
    entries.removeAll()
    lock.unlock()
  }

  func drain() -> [(filename: String, image: CGImage)] {
    lock.lock()
    guard !entries.isEmpty else {
      lock.unlock()
      return []
    }
    let drained = entries
    entries.removeAll()
    lock.unlock()
    return drained
  }
}

private struct WeakVaultBox {
  weak var store: SessionVaultStore?
}

/// Views read downsampled preview images from a byte-bounded memory cache; disk reads, PNG
/// encoding, preview downsampling, and decoding run on `ioQueue`.
@MainActor @Observable
final class SessionVaultStore {
  nonisolated static let maxStoredRecords = 200
  nonisolated static let maxCachedImages = 16
  nonisolated static let maxCacheBytes = 24 * 1024 * 1024
  nonisolated static let maxPreviewPixelDimension = 1280
  nonisolated private static let sessionsFilename = "sessions.json"
  nonisolated private static let vaultDirectoryPermissions = 0o700

  private(set) var records: [SessionRecord] = []
  private(set) var pinnedRecordID: UUID?
  private var cachedImages: [String: NSImage] = [:]
  @ObservationIgnored private var cachedImageBytes: [String: Int] = [:]
  @ObservationIgnored private(set) var totalCachedImageBytes = 0
  @ObservationIgnored private var cachedImageOrder: [String] = []
  @ObservationIgnored private var pendingImageLoads: Set<String> = []
  @ObservationIgnored private var summaryTasks: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private let stagedPreviews = StagedPreviewBuffer()
  @ObservationIgnored private let pasteboard: NSPasteboard
  @ObservationIgnored private var copyRequestGeneration: UInt64 = 0
  let storageDirectory: URL
  @ObservationIgnored nonisolated private static let ioQueue = DispatchQueue(
    label: "app.sillies.session-vault", qos: .utility)
  @ObservationIgnored private static var activeStoresByDirectory: [URL: WeakVaultBox] = [:]

  var pendingSummaryCount: Int {
    summaryTasks.count
  }

  init(directory: URL? = nil, pasteboard: NSPasteboard = .general) {
    self.pasteboard = pasteboard
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
    loadSynchronously()
    resumePendingSummaries()
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
        image, preencodedPNGData: pngData, filename: filename, preparePreview: needsDownsampling)
    }
    records.insert(updated, at: 0)
    if records.count > Self.maxStoredRecords {
      let removed = records.suffix(from: Self.maxStoredRecords)
      for old in removed {
        if let file = old.imageFilename {
          evictCachedImage(for: file)
          deleteImageAsync(filename: file)
        }
      }
      records = Array(records.prefix(Self.maxStoredRecords))
    }
    persistAsync()
    if updated.summaryPending {
      scheduleSummaryRefinement(for: updated)
    }
  }

  func update(_ record: SessionRecord) {
    guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
    records[index] = record
    persistAsync()
  }

  func completePendingSummary(id: UUID, summary: String, actionItems: [String]) {
    summaryTasks.removeValue(forKey: id)
    guard let index = records.firstIndex(where: { $0.id == id }) else { return }
    var updated = records[index]
    updated.summary = summary
    updated.actionItems = actionItems
    updated.summaryPending = false
    records[index] = updated
    persistAsync()
  }

  func resumePendingSummaries() {
    for record in records where record.summaryPending {
      scheduleSummaryRefinement(for: record)
    }
  }

  func flushPendingSummaries() async {
    resumePendingSummaries()
    while !summaryTasks.isEmpty {
      let current = Array(summaryTasks.values)
      for task in current {
        await task.value
      }
    }
    await flush()
  }

  func cancelPendingSummaries() {
    for task in summaryTasks.values { task.cancel() }
    summaryTasks.removeAll()
  }

  func setPinnedRecord(_ id: UUID?) {
    pinnedRecordID = id
    if let id, let record = records.first(where: { $0.id == id }) {
      prepareImage(for: record)
    }
  }

  func remove(id: UUID) {
    summaryTasks[id]?.cancel()
    summaryTasks.removeValue(forKey: id)
    if pinnedRecordID == id { pinnedRecordID = nil }
    guard let index = records.firstIndex(where: { $0.id == id }) else { return }
    let removed = records.remove(at: index)
    if let file = removed.imageFilename {
      evictCachedImage(for: file)
      deleteImageAsync(filename: file)
    }
    persistAsync()
  }

  func clearAll() {
    for task in summaryTasks.values { task.cancel() }
    summaryTasks.removeAll()
    pinnedRecordID = nil
    let files = records.compactMap(\.imageFilename)
    records.removeAll()
    cachedImages.removeAll()
    cachedImageBytes.removeAll()
    totalCachedImageBytes = 0
    cachedImageOrder.removeAll()
    pendingImageLoads.removeAll()
    stagedPreviews.removeAll()
    for file in files { deleteImageAsync(filename: file) }
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
    Self.ioQueue.async {
      dispatchPrecondition(condition: .notOnQueue(.main))
      let modes: [CFString] = [
        CFRunLoopMode.commonModes.rawValue,
        CFRunLoopMode.defaultMode.rawValue,
        RunLoop.Mode.modalPanel.rawValue as CFString,
        RunLoop.Mode.eventTracking.rawValue as CFString,
      ]
      let mainLoop = CFRunLoopGetMain()
      CFRunLoopPerformBlock(mainLoop, modes as CFArray) {
        completion()
      }
      CFRunLoopWakeUp(mainLoop)
    }
  }

  func drainStagedPreviewsForTermination() {
    drainStagedPreviews()
  }

  func imageURL(for record: SessionRecord) -> URL? {
    guard let filename = record.imageFilename else { return nil }
    return storageDirectory.appendingPathComponent(filename)
  }

  /// Non-blocking cache lookup for SwiftUI view rendering.
  func cachedImage(for record: SessionRecord) -> NSImage? {
    drainStagedPreviews()
    guard let filename = record.imageFilename else { return nil }
    if let image = cachedImages[filename] {
      if cachedImageOrder.last != filename {
        cachedImageOrder.removeAll { $0 == filename }
        cachedImageOrder.append(filename)
      }
      return image
    }
    return nil
  }

  /// Decodes a downsampled preview of the snapshot PNG on `ioQueue` if not already in memory.
  func prepareImage(for record: SessionRecord) {
    drainStagedPreviews()
    guard let filename = record.imageFilename,
      cachedImages[filename] == nil,
      !pendingImageLoads.contains(filename),
      let url = imageURL(for: record)
    else { return }
    pendingImageLoads.insert(filename)
    let staged = stagedPreviews
    Self.ioQueue.async { [weak self] in
      if let decoded = Self.decodePreviewCGImage(at: url) {
        staged.append(filename: filename, image: decoded)
      }
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.pendingImageLoads.remove(filename)
        self.drainStagedPreviews()
      }
    }
  }

  func copyText(_ text: String) {
    guard !text.isEmpty else { return }
    copyRequestGeneration &+= 1
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  func copyImage(for record: SessionRecord) {
    copyRequestGeneration &+= 1
    let requestGeneration = copyRequestGeneration
    let expectedChangeCount = pasteboard.changeCount
    let fallbackCG = cachedImage(for: record)?.cgImage(
      forProposedRect: nil, context: nil, hints: nil)
    guard let filename = record.imageFilename, let url = imageURL(for: record) else {
      guard let fallbackCG else { return }
      Self.ioQueue.async { [weak self] in
        guard let pngData = Self.encodePNGData(from: fallbackCG) else { return }
        Task { @MainActor [weak self] in
          guard let self,
            self.copyRequestGeneration == requestGeneration,
            self.pasteboard.changeCount == expectedChangeCount
          else { return }
          self.pasteboard.clearContents()
          self.pasteboard.setData(pngData, forType: .png)
        }
      }
      return
    }
    let needsPreviewCache = cachedImage(for: record) == nil
    Self.ioQueue.async { [weak self] in
      let diskPNGData = try? Data(contentsOf: url)
      let resolvedPNGData = diskPNGData ?? fallbackCG.flatMap { Self.encodePNGData(from: $0) }
      let previewCG = needsPreviewCache ? Self.decodePreviewCGImage(at: url) : nil
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let previewCG,
          self.records.contains(where: { $0.imageFilename == filename })
        {
          self.storeCachedImage(previewCG, for: filename)
        }
        guard
          self.copyRequestGeneration == requestGeneration,
          self.pasteboard.changeCount == expectedChangeCount,
          let resolvedPNGData
        else { return }
        self.pasteboard.clearContents()
        self.pasteboard.setData(resolvedPNGData, forType: .png)
      }
    }
  }

  private func scheduleSummaryRefinement(for record: SessionRecord) {
    guard summaryTasks[record.id] == nil else { return }
    let recordID = record.id
    let sourceText = record.primaryText
    let fallbackContext = record.summary
    summaryTasks[recordID] = Task { @MainActor [weak self] in
      let (summary, actions) = await SessionSummarizer.summarizeOnWorker(
        text: sourceText, fallbackContext: fallbackContext)
      guard !Task.isCancelled, let self else { return }
      self.completePendingSummary(id: recordID, summary: summary, actionItems: actions)
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

  private func storeCachedImage(_ cgImage: CGImage, for filename: String) {
    let byteCost = Self.estimatedByteSize(of: cgImage)
    if let previousCost = cachedImageBytes.removeValue(forKey: filename) {
      totalCachedImageBytes = max(0, totalCachedImageBytes - previousCost)
      cachedImageOrder.removeAll { $0 == filename }
    }
    let pinnedFilename =
      pinnedRecordID.flatMap { id in records.first(where: { $0.id == id })?.imageFilename }
    while !cachedImageOrder.isEmpty
      && (totalCachedImageBytes + byteCost > Self.maxCacheBytes
        || cachedImageOrder.count >= Self.maxCachedImages)
    {
      let evictionIndex =
        cachedImageOrder.firstIndex(where: { $0 != pinnedFilename })
        ?? cachedImageOrder.startIndex
      let oldest = cachedImageOrder.remove(at: evictionIndex)
      cachedImages.removeValue(forKey: oldest)
      if let oldBytes = cachedImageBytes.removeValue(forKey: oldest) {
        totalCachedImageBytes = max(0, totalCachedImageBytes - oldBytes)
      }
    }
    guard byteCost <= Self.maxCacheBytes else { return }
    let image = NSImage(
      cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    cachedImageOrder.append(filename)
    cachedImages[filename] = image
    cachedImageBytes[filename] = byteCost
    totalCachedImageBytes += byteCost
  }

  private func evictCachedImage(for filename: String) {
    cachedImages.removeValue(forKey: filename)
    if let removedBytes = cachedImageBytes.removeValue(forKey: filename) {
      totalCachedImageBytes = max(0, totalCachedImageBytes - removedBytes)
    }
    cachedImageOrder.removeAll { $0 == filename }
    pendingImageLoads.remove(filename)
    stagedPreviews.remove(filename: filename)
  }

  private nonisolated static func estimatedByteSize(of cgImage: CGImage) -> Int {
    max(cgImage.bytesPerRow * cgImage.height, cgImage.width * cgImage.height * 4)
  }

  private nonisolated static func makePreviewCGImage(from cgImage: CGImage) -> CGImage {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let maxDimension = max(cgImage.width, cgImage.height)
    guard maxDimension > maxPreviewPixelDimension, maxDimension > 0 else { return cgImage }
    let scale = Double(maxPreviewPixelDimension) / Double(maxDimension)
    let targetWidth = max(1, Int((Double(cgImage.width) * scale).rounded()))
    let targetHeight = max(1, Int((Double(cgImage.height) * scale).rounded()))
    let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        bitsPerComponent: 8,
        bytesPerRow: targetWidth * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return cgImage }
    context.interpolationQuality = .medium
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    return context.makeImage() ?? cgImage
  }

  private nonisolated static func decodePreviewCGImage(at url: URL) -> CGImage? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    return autoreleasepool {
      let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
      guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary)
      else { return nil }
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPreviewPixelDimension,
      ]
      return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
  }

  nonisolated static func encodePNGData(from cgImage: CGImage) -> Data? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    return autoreleasepool {
      let rep = NSBitmapImageRep(cgImage: cgImage)
      return rep.representation(using: .png, properties: [:])
    }
  }

  private func loadSynchronously() {
    let fileURL = storageDirectory.appendingPathComponent(Self.sessionsFilename)
    guard let data = try? Data(contentsOf: fileURL) else { return }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    if let decoded = try? decoder.decode([SessionRecord].self, from: data) {
      records = decoded
    }
  }

  private func persistAsync() {
    let snapshot = records
    let directory = storageDirectory
    let fileURL = directory.appendingPathComponent(Self.sessionsFilename)
    Self.ioQueue.async {
      dispatchPrecondition(condition: .notOnQueue(.main))
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      do {
        let data = try encoder.encode(snapshot)
        Self.writeAtomically(data, to: fileURL, in: directory)
      } catch {
        fputs(
          "SessionVaultStore failed to encode session records: \(error.localizedDescription)\n",
          stderr)
      }
    }
  }

  private func saveImageAsync(
    _ cgImage: CGImage, preencodedPNGData: Data?, filename: String, preparePreview: Bool
  ) {
    let directory = storageDirectory
    let fileURL = directory.appendingPathComponent(filename)
    let staged = stagedPreviews
    Self.ioQueue.async { [weak self] in
      dispatchPrecondition(condition: .notOnQueue(.main))
      if preparePreview {
        let preview = Self.makePreviewCGImage(from: cgImage)
        staged.append(filename: filename, image: preview)
        Task { @MainActor [weak self] in
          self?.drainStagedPreviews()
        }
      }
      if let data = preencodedPNGData ?? Self.encodePNGData(from: cgImage) {
        Self.writeAtomically(data, to: fileURL, in: directory)
      }
    }
  }

  private nonisolated static func writeAtomically(
    _ data: Data,
    to fileURL: URL,
    in directory: URL
  ) {
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: vaultDirectoryPermissions])
      try data.write(to: fileURL, options: .atomic)
    } catch {
      fputs(
        "SessionVaultStore failed to write \(fileURL.lastPathComponent): \(error.localizedDescription)\n",
        stderr)
    }
  }

  private func deleteImageAsync(filename: String) {
    let fileURL = storageDirectory.appendingPathComponent(filename)
    Self.ioQueue.async {
      dispatchPrecondition(condition: .notOnQueue(.main))
      try? FileManager.default.removeItem(at: fileURL)
    }
  }
}
