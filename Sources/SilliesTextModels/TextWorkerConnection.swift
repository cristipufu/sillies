import Foundation
import SilliesInference

/// Text-specific exchange over the shared, cancellable worker transport.
final class TextWorkerConnection: Sendable {
  private let responseTimeout: TimeInterval
  private let connection: InferenceWorkerConnection

  init(executable: URL, responseTimeout: TimeInterval = 120) throws {
    self.responseTimeout = responseTimeout
    connection = try InferenceWorkerConnection(executable: executable)
  }

  func stream(_ request: TextInferenceRequest, receive: @escaping TextDeltaSink) async throws
    -> TextGenerationOutput
  {
    let deadline = InferenceDeadline(timeout: responseTimeout)
    try await Task.detached {
      try self.connection.send(request, timeout: deadline.remaining())
    }.value
    var receivedBytes = 0
    var receivedText = ""
    while true {
      try Task.checkCancellation()
      let event = try await Task.detached {
        try self.connection.receive(
          TextInferenceEvent.self, timeout: deadline.remaining())
      }.value
      switch event {
      case .delta(let text):
        guard !text.isEmpty else { throw TextGenerationFailure(reason: .emptyDelta) }
        guard text.utf8.count <= TextInferenceWire.maximumMessageBytes / 2 - receivedBytes
        else {
          throw TextGenerationFailure(reason: .responseSizeLimit)
        }
        receivedBytes += text.utf8.count
        receivedText += text
        try await receive(text)
        try await Task.detached {
          try self.connection.send(
            TextInferenceAcknowledgement(), timeout: deadline.remaining())
        }.value
      case .finished(let response):
        let output = try result(response)
        guard
          receivedText.trimmingCharacters(in: .whitespacesAndNewlines)
            == output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
          throw TextGenerationFailure(reason: .streamMismatch)
        }
        return output
      }
    }
  }

  private func result(_ response: TextInferenceResponse) throws -> TextGenerationOutput {
    if response.failureCode == .contextLimit { throw TextModelError.contextLimit }
    if let failure = response.generationFailure { throw failure }
    if let failure = response.failure { throw TextModelError.unavailable(failure) }
    guard let text = response.text,
      !text.isEmpty || !(response.calls ?? []).isEmpty || response.inputTokens != nil
    else {
      throw TextGenerationFailure(reason: .emptyResponse)
    }
    return .init(
      text: text, calls: response.calls ?? [], inputTokens: response.inputTokens,
      metrics: response.metrics, reasoningContent: response.reasoningContent)
  }

  func stop() { connection.stop() }
  func reap() async { await connection.reap() }
}
