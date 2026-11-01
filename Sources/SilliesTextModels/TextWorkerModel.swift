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
    let output = try await complete(request)
    guard output.calls.isEmpty else { throw TextModelError.invalidResponse }
    return output.text
  }
  func complete(_ request: TextGenerationRequest) async throws -> TextGenerationOutput {
    try await stream(request, receive: { _ in })
  }
  func stream(_ request: TextGenerationRequest, receive: @escaping TextDeltaSink) async throws
    -> TextGenerationOutput
  {
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
        let output = try await worker.stream(message, receive: receive)
        try Task.checkCancellation()
        return output
      } catch TextModelError.contextLimit {
        throw TextModelError.contextLimit
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
