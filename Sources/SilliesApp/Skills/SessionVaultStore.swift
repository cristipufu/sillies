import AppKit
import Foundation
import Observation
import SilliesCore

/// Persists captured window snapshots, transcripts, focus sprints, and stashed items locally.
@MainActor @Observable
final class SessionVaultStore {
  private static let maxStoredRecords = 200
  private static let sessionsFilename = "sessions.json"

  private(set) var records: [SessionRecord] = []
  let storageDirectory: URL
  private let ioQueue = DispatchQueue(label: "app.sillies.session-vault", qos: .utility)

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
      saveImageAsync(image, filename: filename)
    }
    records.insert(updated, at: 0)
    if records.count > Self.maxStoredRecords {
      let removed = records.suffix(from: Self.maxStoredRecords)
      for old in removed {
        if let file = old.imageFilename { deleteImageAsync(filename: file) }
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
    if let file = removed.imageFilename { deleteImageAsync(filename: file) }
    persistAsync()
  }

  func clearAll() {
    let files = records.compactMap(\.imageFilename)
    records.removeAll()
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

  func loadImage(for record: SessionRecord) -> NSImage? {
    guard let url = imageURL(for: record) else { return nil }
    return NSImage(contentsOf: url)
  }

  func copyText(_ text: String) {
    guard !text.isEmpty else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  func copyImage(for record: SessionRecord) {
    guard let image = loadImage(for: record) else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects([image])
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
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let rep = NSBitmapImageRep(cgImage: cgImage)
      if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: fileURL, options: .atomic)
      }
    }
  }

  private func deleteImageAsync(filename: String) {
    let fileURL = storageDirectory.appendingPathComponent(filename)
    ioQueue.async {
      try? FileManager.default.removeItem(at: fileURL)
    }
  }
}
