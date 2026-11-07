import Foundation

/// Bounded, cancellable copying; a backup never follows a saved filename through a symlink.
public enum VaultAttachmentCopy {
  private static let bufferBytes = 256 * 1_024
  public static func copy(
    _ name: String, from source: VaultFileStorage, to destination: VaultFileStorage
  ) throws {
    let original = try source.attachmentURL(for: name)
    let target = try destination.attachmentURL(for: name)
    if FileManager.default.fileExists(atPath: target.path) { return }
    let values = try original.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
      throw CocoaError(.fileReadCorruptFile)
    }
    guard
      FileManager.default.createFile(
        atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600])
    else { throw CocoaError(.fileWriteUnknown) }
    let input = try FileHandle(forReadingFrom: original)
    let output = try FileHandle(forWritingTo: target)
    defer {
      do { try input.close() } catch { fputs("Backup input close failed: \(error)\n", stderr) }
      do { try output.close() } catch { fputs("Backup output close failed: \(error)\n", stderr) }
    }
    while true {
      try Task.checkCancellation()
      guard let bytes = try input.read(upToCount: bufferBytes), !bytes.isEmpty else { break }
      try output.write(contentsOf: bytes)
    }
    try output.synchronize()
  }
}
