import Foundation

actor TextWorkerModel: PreparedTextModel {
  private let configuration: TextModelPreparation
  private let executable: URL
  private var connection: TextWorkerConnection?
  private var busy = false

  init(configuration: TextModelPreparation, executable: URL) {
    self.configuration = configuration
    self.executable = executable
  }

  func generate(_ request: TextGenerationRequest) async throws -> String {
    guard !busy else { throw TextModelError.busy }
    busy = true
    defer { busy = false }
    try Task.checkCancellation()
    let worker = try connection ?? TextWorkerConnection(executable: executable)
    connection = worker
    let message = TextInferenceRequest(configuration: configuration, generation: request)
    return try await withTaskCancellationHandler {
      do {
        try Task.checkCancellation()
        let output = try await Task.detached(priority: .utility) { try worker.generate(message) }
          .value
        try Task.checkCancellation()
        return output
      } catch {
        worker.stop()
        await worker.reap()
        connection = nil
        throw error
      }
    } onCancel: {
      worker.stop()
    }
  }

  func stop() async {
    guard let worker = connection else { return }
    connection = nil
    worker.stop()
    await worker.reap()
  }
}
