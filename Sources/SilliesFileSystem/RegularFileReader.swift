import Darwin
import Foundation

/// Synchronous descriptor ownership, confined to the caller's worker for the entire operation.
package final class RegularFileReader {
  private static let chunkBytes = 1_048_576
  private let file: FileHandle

  private init(url: URL) throws {
    // Never follow the final symlink or block opening a substituted FIFO.
    let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else {
        errno = EINVAL
        return -1
      }
      return open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
    }
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
  }

  package static func withFile<T>(at url: URL, _ read: (RegularFileReader) throws -> T) throws -> T
  {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let reader = try Self(url: url)
    defer {
      do { try reader.file.close() } catch {
        fputs("Local file close failed: \(error.localizedDescription)\n", stderr)
      }
    }
    _ = try reader.fingerprint()
    return try read(reader)
  }

  package func fingerprint() throws -> FileFingerprint { try FileFingerprint.read(from: file) }
  package func readChunk() throws -> Data? { try file.read(upToCount: Self.chunkBytes) }
}
