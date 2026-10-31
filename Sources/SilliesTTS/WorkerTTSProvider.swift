import Foundation

/// Provider identities select shipped runtime adapters, never executable code from a model download.
package struct WorkerTTSProvider: TTSProvider {
  package let id: String
  private let executable: URL

  package init(id: String, executable: URL) {
    self.id = id
    self.executable = executable
  }

  package func prepare(_ configuration: TTSPreparation) async throws -> any PreparedTTSModel {
    guard configuration.providerID == id else { throw TTSError.invalidRequest }
    try Task.checkCancellation()
    return TTSWorkerModel(configuration: configuration, executable: executable)
  }
}
