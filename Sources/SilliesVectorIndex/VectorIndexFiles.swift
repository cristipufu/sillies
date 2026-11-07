import CryptoKit
import Foundation
import SilliesPersistence

/// Files for a disposable, crash-recoverable native index. SQLite remains authoritative.
struct VectorIndexFiles {
  private static let maximumManifestBytes = 16_384
  let directory: URL
  private let files: VaultFileStorage
  var index: URL { directory.appendingPathComponent("vectors.index") }
  var backing: URL { directory.appendingPathComponent("vectors.ivf") }
  private var manifest: URL { directory.appendingPathComponent("checkpoint.json") }
  private var dirty: URL { directory.appendingPathComponent("pending") }
  private static let filenames = [
    "vectors.index", "vectors.ivf", "vectors.next", "checkpoint.json", "pending", "opening",
  ]

  init(vault: URL, provider: String, space: String) {
    let identity = Data((provider + "\0" + space).utf8)
    let name = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
    directory = vault.appendingPathComponent("VectorIndexes", isDirectory: true)
      .appendingPathComponent(name, isDirectory: true)
    files = VaultFileStorage(directory: directory)
  }

  func read() throws -> VectorIndexCheckpoint? {
    try validateDirectories()
    guard !FileManager.default.fileExists(atPath: dirty.path),
      !FileManager.default.fileExists(atPath: directory.appendingPathComponent("opening").path),
      FileManager.default.fileExists(atPath: manifest.path),
      FileManager.default.fileExists(atPath: index.path)
    else { return nil }
    let values = try manifest.resourceValues(forKeys: [
      .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      let size = values.fileSize, size <= Self.maximumManifestBytes
    else {
      fputs("Vector checkpoint is invalid; rebuilding its derived cache.\n", stderr)
      return nil
    }
    do {
      return try JSONDecoder().decode(VectorIndexCheckpoint.self, from: Data(contentsOf: manifest))
    } catch is DecodingError {
      fputs("Vector checkpoint is invalid; rebuilding its derived cache.\n", stderr)
      return nil
    }
  }

  func openIndex(dimensions: Int) throws -> NativeVectorIndex {
    for file in [index, backing] where FileManager.default.fileExists(atPath: file.path) {
      let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true else {
        throw CocoaError(.fileReadCorruptFile)
      }
    }
    try files.write(Data([1]), named: "opening")
    try synchronize(directory.appendingPathComponent("opening"))
    let opened = try NativeVectorIndex(opening: index, dimensions: dimensions)
    try files.removeAttachment(named: "opening")
    return opened
  }

  func beginWrite() throws {
    try validateDirectories()
    try files.write(Data([1]), named: "pending")
    try synchronize(dirty)
  }

  func publish(_ checkpoint: VectorIndexCheckpoint, index: NativeVectorIndex) throws {
    let temporary = directory.appendingPathComponent("vectors.next")
    try index.checkpoint(to: temporary)
    try synchronize(temporary)
    if FileManager.default.fileExists(atPath: self.index.path) {
      _ = try FileManager.default.replaceItemAt(self.index, withItemAt: temporary)
    } else {
      try FileManager.default.moveItem(at: temporary, to: self.index)
    }
    try files.write(try JSONEncoder().encode(checkpoint), named: "checkpoint.json")
    try synchronize(manifest)
    try files.removeAttachment(named: "pending")
  }

  func reset() throws {
    try validateDirectories()
    for name in Self.filenames {
      try files.removeAttachment(named: name)
    }
    try beginWrite()
  }

  /// Remove one retired cache per maintenance call, never recurse through a saved or arbitrary path.
  static func removeObsolete(in vault: URL, preserving names: Set<String>) throws -> Bool {
    let root = vault.appendingPathComponent("VectorIndexes", isDirectory: true)
    guard FileManager.default.fileExists(atPath: root.path) else { return false }
    try validateDirectory(root)
    guard
      let children = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        options: [.skipsSubdirectoryDescendants])
    else { throw CocoaError(.fileReadUnknown) }
    for case let child as URL in children {
      try Task.checkCancellation()
      let name = child.lastPathComponent
      guard name.count == SHA256.Digest.byteCount * 2,
        name.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
        !names.contains(name)
      else { continue }
      try validateDirectory(child)
      let files = VaultFileStorage(directory: child)
      for filename in filenames { try files.removeAttachment(named: filename) }
      // rmdir only succeeds for an empty directory; unknown files are never removed recursively.
      guard rmdir(child.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
      return true
    }
    return false
  }

  private func validateDirectories() throws {
    for url in [directory.deletingLastPathComponent(), directory]
    where FileManager.default.fileExists(atPath: url.path) {
      try Self.validateDirectory(url)
    }
  }

  private static func validateDirectory(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw CocoaError(.fileReadCorruptFile)
    }
  }

  private func synchronize(_ url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    do {
      try handle.synchronize()
      try handle.close()
    } catch {
      do { try handle.close() } catch { fputs("Index checkpoint close failed: \(error)\n", stderr) }
      throw error
    }
  }
}
