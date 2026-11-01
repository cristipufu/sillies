import Darwin
import Foundation

/// Descriptor-based identity includes ctime, so restoring mtime cannot hide an ordinary file edit.
package struct FileFingerprint: Hashable, Sendable {
  private static let nanosecondsPerSecond = 1_000_000_000
  let device: dev_t
  let inode: ino_t
  let generation: UInt32
  package let size: Int64
  let mode: mode_t
  let modifiedSeconds: time_t
  let modifiedNanoseconds: Int
  let changedSeconds: time_t
  let changedNanoseconds: Int
  let createdSeconds: time_t
  let createdNanoseconds: Int

  // Coarse change timestamps cannot reliably invalidate same-second edits; always hash those files.
  package var supportsReuse: Bool {
    changedNanoseconds > 0 && changedNanoseconds < Self.nanosecondsPerSecond
  }

  static func read(from file: FileHandle) throws -> Self {
    var status = stat()
    guard fstat(file.fileDescriptor, &status) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard status.st_mode & S_IFMT == S_IFREG else { throw POSIXError(.EINVAL) }
    return .init(
      device: status.st_dev, inode: status.st_ino, generation: status.st_gen,
      size: status.st_size, mode: status.st_mode,
      modifiedSeconds: status.st_mtimespec.tv_sec,
      modifiedNanoseconds: status.st_mtimespec.tv_nsec,
      changedSeconds: status.st_ctimespec.tv_sec,
      changedNanoseconds: status.st_ctimespec.tv_nsec,
      createdSeconds: status.st_birthtimespec.tv_sec,
      createdNanoseconds: status.st_birthtimespec.tv_nsec)
  }
}
