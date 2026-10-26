import AppKit
import Foundation
import ImageIO
import Observation
import SilliesCore

/// Persists captured window snapshots, transcripts, focus sprints, and stashed items locally.
/// Views read downsampled preview images from a byte-bounded memory cache; disk reads, PNG
/// encoding, and decoding run on `ioQueue`.
@MainActor @Observable
final class SessionVaultStore {
  nonisolated static let maxStoredRecords = 200
  nonisolated static let maxCachedImages = 16
  nonisolated static let maxCacheBytes = 24 * 1024 * 1024
  nonisolated static let maxPreviewPixelDimension = 1280
  nonisolated private static let sessionsFilename = "sessions.json"

  private(set) var records: [SessionRecord] = []
  private var cachedImages: [String: NSImage] = [:]
  @ObservationIgnored private var cachedImageBytes: [String: Int] = [:]
  @ObservationIgnored private(set) var totalCachedImageBytes = 0
  @ObservationIgnored private var cachedImageOrder: [String] = []
  @ObservationIgnored private var pendingImageLoads: Set<String> = []
  let storageDirectory: URL
  @ObservationIgnored private let ioQueue = DispatchQueue(
    label: "app.sillies.session-vault", qos: .utility)

  init(directory: URL? = nil) {
    if let directory {
      storageDirectory = directory
    } else {
      let appSupport =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory())
      storageDirectory = appSupport.appendingPathComponent("Sillies/Vault", isDirectory: true)
    }
    loadSynchronously()
  }

  func add(_ record: SessionRecord, image: CGImage? = nil) {
    var updated = record
    if let image {
      let filename = "\(record.id.uuidString).png"
      updated.imageFilename = filename
      let preview = Self.makePreviewCGImage(from: image)
      storeCachedImage(preview, for: filename)
      saveImageAsync(image, filename: filename)
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
  }

  func update(_ record: SessionRecord) {
    guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
    records[index] = record
    persistAsync()
  }

  func remove(id: UUID) {
    guard let index = records.firstIndex(where: { $0.id == id }) else { return }
    let removed = records.remove(at: index)
    if let file = removed.imageFilename {
      evictCachedImage(for: file)
      deleteImageAsync(filename: file)
    }
    persistAsync()
  }

  func clearAll() {
    let files = records.compactMap(\.imageFilename)
    records.removeAll()
    cachedImages.removeAll()
    cachedImageBytes.removeAll()
    totalCachedImageBytes = 0
    cachedImageOrder.removeAll()
    pendingImageLoads.removeAll()
    for file in files { deleteImageAsync(filename: file) }
    persistAsync()
  }

  func flush() {
    ioQueue.sync {}
  }

  func imageURL(for record: SessionRecord) -> URL? {
    guard let filename = record.imageFilename else { return nil }
    return storageDirectory.appendingPathComponent(filename)
  }

  /// Non-blocking cache lookup for SwiftUI view rendering.
  func cachedImage(for record: SessionRecord) -> NSImage? {
    guard let filename = record.imageFilename else { return nil }
    return cachedImages[filename]
  }

  /// Decodes a downsampled preview of the snapshot PNG on `ioQueue` if not already in memory.
  func prepareImage(for record: SessionRecord) {
    guard let filename = record.imageFilename,
      cachedImages[filename] == nil,
      !pendingImageLoads.contains(filename),
      let url = imageURL(for: record)
    else { return }
    pendingImageLoads.insert(filename)
    ioQueue.async { [weak self] in
      let decoded = Self.decodePreviewCGImage(at: url)
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.pendingImageLoads.remove(filename)
        guard let decoded,
          self.records.contains(where: { $0.imageFilename == filename })
        else { return }
        self.storeCachedImage(decoded, for: filename)
      }
    }
  }

  func copyText(_ text: String) {
    guard !text.isEmpty else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  func copyImage(for record: SessionRecord) {
    guard let filename = record.imageFilename, let url = imageURL(for: record) else {
      if let cached = cachedImage(for: record) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([cached])
      }
      return
    }
    let fallbackPreview = cachedImage(for: record)
    ioQueue.async { [weak self] in
      let fullCG = Self.decodeFullCGImage(at: url)
      let previewCG = fullCG.map { Self.makePreviewCGImage(from: $0) }
      Task { @MainActor [weak self] in
        if let previewCG {
          self?.storeCachedImage(previewCG, for: filename)
        }
        if let fullCG {
          let nsImage = NSImage(
            cgImage: fullCG, size: NSSize(width: fullCG.width, height: fullCG.height))
          let pasteboard = NSPasteboard.general
          pasteboard.clearContents()
          pasteboard.writeObjects([nsImage])
        } else if let fallbackPreview {
          let pasteboard = NSPasteboard.general
          pasteboard.clearContents()
          pasteboard.writeObjects([fallbackPreview])
        }
      }
    }
  }

  private func storeCachedImage(_ cgImage: CGImage, for filename: String) {
    let byteCost = Self.estimatedByteSize(of: cgImage)
    if let previousCost = cachedImageBytes.removeValue(forKey: filename) {
      totalCachedImageBytes = max(0, totalCachedImageBytes - previousCost)
      cachedImageOrder.removeAll { $0 == filename }
    }
    while !cachedImageOrder.isEmpty
      && (totalCachedImageBytes + byteCost > Self.maxCacheBytes
        || cachedImageOrder.count >= Self.maxCachedImages)
    {
      let oldest = cachedImageOrder.removeFirst()
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
  }

  private nonisolated static func estimatedByteSize(of cgImage: CGImage) -> Int {
    max(cgImage.bytesPerRow * cgImage.height, cgImage.width * cgImage.height * 4)
  }

  private nonisolated static func makePreviewCGImage(from cgImage: CGImage) -> CGImage {
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

  private nonisolated static func decodeFullCGImage(at url: URL) -> CGImage? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    return autoreleasepool {
      guard let data = try? Data(contentsOf: url),
        let rep = NSBitmapImageRep(data: data)
      else { return nil }
      return rep.cgImage
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
    ioQueue.async {
      dispatchPrecondition(condition: .notOnQueue(.main))
      try? FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      if let data = try? encoder.encode(snapshot) {
        try? data.write(to: fileURL, options: .atomic)
      }
    }
  }

  private func saveImageAsync(_ cgImage: CGImage, filename: String) {
    let directory = storageDirectory
    let fileURL = directory.appendingPathComponent(filename)
    ioQueue.async {
      dispatchPrecondition(condition: .notOnQueue(.main))
      try? FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      let rep = NSBitmapImageRep(cgImage: cgImage)
      if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: fileURL, options: .atomic)
      }
    }
  }

  private func deleteImageAsync(filename: String) {
    let fileURL = storageDirectory.appendingPathComponent(filename)
    ioQueue.async {
      dispatchPrecondition(condition: .notOnQueue(.main))
      try? FileManager.default.removeItem(at: fileURL)
    }
  }
}
