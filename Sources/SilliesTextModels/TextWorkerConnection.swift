import Foundation
import SilliesInference

/// Text-specific exchange over the shared, cancellable worker transport.
final class TextWorkerConnection: Sendable {
  private static let responseTimeout: TimeInterval = 120
  private let connection: InferenceWorkerConnection

  init(executable: URL) throws {
    connection = try InferenceWorkerConnection(executable: executable)
  }

  func generate(_ request: TextInferenceRequest) throws -> String {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try connection.send(request, timeout: Self.responseTimeout)
    let response = try connection.receive(TextInferenceResponse.self, timeout: Self.responseTimeout)
    if let failure = response.failure { throw TextModelError.unavailable(failure) }
    guard let text = response.text, !text.isEmpty else { throw TextModelError.invalidResponse }
    return text
  }

  func stop() { connection.stop() }
  func reap() async { await connection.reap() }
}
