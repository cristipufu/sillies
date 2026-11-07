import Foundation

extension VaultLibrary {
  package nonisolated func prepareRestore(from source: URL) async throws {
    try await restoreWorker.prepare(from: source)
  }
  package nonisolated func preparedRestoreDirectory() async throws -> URL? {
    try await restoreWorker.preparedDirectory()
  }
  package nonisolated func cancelPreparedRestore() async throws {
    try await restoreWorker.cancelPreparedRestore()
  }
}
