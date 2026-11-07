import Foundation
import SilliesCore

public enum VaultStorageInspection {
  public static func measure(_ directory: URL) throws -> VaultStorageUsage {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey]
    var traversalError: Error?
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: Array(keys),
        errorHandler: { _, error in
          traversalError = error
          return false
        })
    else { throw CocoaError(.fileReadUnknown) }
    var usage = VaultStorageUsage()
    let rootPath = directory.standardizedFileURL.path
    for case let file as URL in enumerator {
      try Task.checkCancellation()
      let values = try file.resourceValues(forKeys: keys)
      guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
      let bytes = Int64(max(0, values.fileAllocatedSize ?? 0))
      if file.deletingLastPathComponent().standardizedFileURL.path != rootPath {
        usage.searchCacheBytes += bytes
      } else if ownsDatabaseFile(file.lastPathComponent, named: VaultDatabase.filename) {
        usage.databaseBytes += bytes
      } else if ownsDatabaseFile(file.lastPathComponent, named: ConversationDatabase.filename) {
        continue
      } else {
        usage.attachmentBytes += bytes
      }
    }
    if let traversalError { throw traversalError }
    return usage
  }

  private static func ownsDatabaseFile(_ filename: String, named database: String) -> Bool {
    [database, database + "-wal", database + "-shm", database + "-journal"].contains(filename)
  }
}
