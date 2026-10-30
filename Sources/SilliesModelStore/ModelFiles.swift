import CryptoKit
import Foundation

/// Filesystem operations run on ModelStore's actor, never on the main actor.
enum ModelFiles {
  private static let hashChunkBytes = 1_048_576
  private static let diskReserveBytes: Int64 = 256 * 1_048_576

  static func isSafeComponent(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".."
      && name.utf8.allSatisfy {
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
          || [45, 46, 95].contains($0)
      }
  }

  static func isSafeRelativePath(_ path: String) -> Bool {
    !path.hasPrefix("/")
      && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
        isSafeComponent(String($0))
      }
  }

  static func child(_ path: String, in root: URL) throws -> URL {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard isSafeRelativePath(path) else { throw ModelStoreError.unsafePath }
    var candidate = root
    // resolvingSymlinksInPath can leave a symlink ancestor unresolved when the
    // final file does not exist. Inspect every existing component explicitly.
    for component in path.split(separator: "/") {
      candidate.appendPathComponent(String(component))
      do {
        let attributes = try FileManager.default.attributesOfItem(atPath: candidate.path)
        guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
          throw ModelStoreError.unsafePath
        }
      } catch CocoaError.fileReadNoSuchFile { continue }
    }
    return candidate
  }

  static func createDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  static func verify(_ artifact: ModelArtifact, at url: URL) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let values = try url.resourceValues(forKeys: [
      .isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      Int64(values.fileSize ?? -1) == artifact.byteCount
    else {
      throw ModelStoreError.invalidArtifact(artifact.path)
    }
    let file = try FileHandle(forReadingFrom: url)
    defer { do { try file.close() } catch { log(error) } }
    var hash = SHA256()
    while let data = try file.read(upToCount: hashChunkBytes), !data.isEmpty {
      try Task.checkCancellation()
      hash.update(data: data)
    }
    guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == artifact.sha256 else {
      throw ModelStoreError.invalidArtifact(artifact.path)
    }
  }

  static func checkCapacity(at root: URL, bytes: Int64) throws {
    let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    if let available = values.volumeAvailableCapacityForImportantUsage,
      available < bytes + diskReserveBytes
    {
      throw ModelStoreError.insufficientSpace
    }
  }

  static func write<T: Encodable>(_ value: T, to url: URL) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try JSONEncoder().encode(value).write(to: url, options: .atomic)
  }

  static func log(_ error: Error) {
    fputs("Speech model storage: \(error.localizedDescription)\n", stderr)
  }
}
