import Darwin
import Foundation

/// Synchronous file operations. The application schedules these on its serialized I/O worker.
public struct VaultFileStorage: Sendable {
  private static let directoryPermissions = 0o700
  public let directory: URL

  public init(directory: URL) { self.directory = directory }

  public func url(for filename: String) throws -> URL {
    guard !filename.isEmpty, filename != ".", filename != "..",
      !filename.contains("/"), !filename.contains("\\"), !filename.contains("\0")
    else { throw CocoaError(.fileWriteInvalidFileName) }
    return directory.appendingPathComponent(filename, isDirectory: false)
  }

  public func attachmentURL(for filename: String) throws -> URL {
    let reserved = [
      SessionRecordRepository.filename, "search.sqlite", "search.sqlite-journal",
      "search.sqlite-wal", "search.sqlite-shm",
    ]
    guard !reserved.contains(where: { filename.caseInsensitiveCompare($0) == .orderedSame }) else {
      throw CocoaError(.fileWriteInvalidFileName)
    }
    return try url(for: filename)
  }

  public func write(_ data: Data, named filename: String) throws {
    let destination = try url(for: filename)
    try prepareDirectory()
    try data.write(to: destination, options: .atomic)
  }

  public func copyAttachment(named filename: String, to destination: VaultFileStorage) throws {
    let source = try attachmentURL(for: filename)
    let target = try destination.attachmentURL(for: filename)
    try destination.prepareDirectory()
    // Export folders have unique IDs, so an existing file is an error rather than an overwrite.
    try FileManager.default.copyItem(at: source, to: target)
  }

  private func prepareDirectory() throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: Self.directoryPermissions])
  }

  public func removeAttachment(named filename: String) throws {
    let destination = try attachmentURL(for: filename)
    // unlink removes files or links only; it cannot recursively delete a directory.
    let result = destination.withUnsafeFileSystemRepresentation { path in
      guard let path else { return EINVAL }
      return unlink(path) == 0 ? 0 : errno
    }
    guard result != 0, result != ENOENT else { return }
    throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO)
  }
}
