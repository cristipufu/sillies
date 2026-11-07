import Foundation
import SilliesPersistence

actor VaultRestoreWorker {
  private let restore: VaultPreparedRestore
  private var isPreparing = false
  init(directory: URL) { restore = .init(directory: directory) }
  func preparedDirectory() throws -> URL? { try restore.preparedDirectory() }
  func cancelPreparedRestore() throws { try restore.cancel() }
  func prepare(from source: URL) async throws {
    guard !isPreparing else { throw CocoaError(.fileWriteFileExists) }
    isPreparing = true
    defer { isPreparing = false }
    try restore.requireAvailable()
    let copy = try await VaultBackupWorker(source: source).write(to: restore.preparationDirectory)
    do {
      let validation = try VaultDatabase(reading: copy)
      try validation.validateBackup()
      try Task.checkCancellation()
      try restore.publish(copy)
    } catch {
      do { try FileManager.default.removeItem(at: copy) } catch {
        fputs("Incomplete restore cleanup failed: \(error)\n", stderr)
      }
      throw error
    }
  }
}
