import AppKit
import Foundation
import Observation
import SilliesCore

/// Persists captured window snapshots, transcripts, focus sprints, and stashed items locally.
/// Views read prepared images from memory; disk reads, PNG encoding, and decoding run on `ioQueue`.
@MainActor @Observable
final class SessionVaultStore {
  private static let maxStoredRecords = 200
  private static let maxCachedImages = 24
  private static let sessionsFilename = "sessions.json"

  private(set) var records: [SessionRecord] = []
  private var cachedImages: [String: NSImage] = [:]
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
      let nsImage = NSImage(
        cgImage: image, size: NSSize(width: image.width, height: image.height))
      storeCachedImage(nsImage, for: filename)
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

  /// Decodes the snapshot PNG on `ioQueue` if not already in memory.
  func prepareImage(for record: SessionRecord) {
    guard let filename = record.imageFilename,
      cachedImages[filename] == nil,
      !pendingImageLoads.contains(filename),
      let url = imageURL(for: record)
    else { return }
    pendingImageLoads.insert(filename)
    ioQueue.async { [weak self] in
      let decoded = Self.decodeCGImage(at: url)
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.pendingImageLoads.remove(filename)
        guard let decoded,
          self.records.contains(where: { $0.imageFilename == filename })
        else { return }
        let nsImage = NSImage(
          cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
        self.storeCachedImage(nsImage, for: filename)
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
    if let cached = cachedImage(for: record) {
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.writeObjects([cached])
      return
    }
    guard let filename = record.imageFilename, let url = imageURL(for: record) else { return }
    ioQueue.async { [weak self] in
      guard let decoded = Self.decodeCGImage(at: url) else { return }
      Task { @MainActor [weak self] in
        let nsImage = NSImage(
          cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
        self?.storeCachedImage(nsImage, for: filename)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
      }
    }
  }

  private func storeCachedImage(_ image: NSImage, for filename: String) {
    if cachedImages[filename] == nil {
      if cachedImageOrder.count >= Self.maxCachedImages {
        let oldest = cachedImageOrder.removeFirst()
        cachedImages.removeValue(forKey: oldest)
      }
      cachedImageOrder.append(filename)
    }
    cachedImages[filename] = image
  }

  private func evictCachedImage(for filename: String) {
    cachedImages.removeValue(forKey: filename)
    cachedImageOrder.removeAll { $0 == filename }
    pendingImageLoads.remove(filename)
  }

  private nonisolated static func decodeCGImage(at url: URL) -> CGImage? {
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
