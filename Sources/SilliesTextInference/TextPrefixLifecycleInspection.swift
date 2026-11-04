import Foundation
import MLX
import SilliesTextModels

/// Exercises cancellation within the helper, including cancellation from the last streamed sink.
enum TextPrefixLifecycleInspection {
  private enum SinkFailure: Error { case intentional }
  private struct Result: Encodable {
    let sinkFailureCleared: Bool
    let cancellationCleared: Bool
    let recoveryRebuilt: Bool
    let snapshot: MLXPrefixSnapshot.Status
    let released: MLXPrefixSnapshot.Status
    let memory: Memory.Snapshot
  }

  static func run(requestURL: URL) async throws {
    let request = try TextInferenceJSON.read(
      TextInferenceRequest.self, from: requestURL,
      maximumBytes: TextInferenceWire.maximumMessageBytes)
    guard let sessionID = request.generation.sessionID else { throw TextModelError.invalidResponse }
    let runtime = MLXTextRuntime()
    _ = try await runtime.generate(request, receive: { _ in })
    do {
      _ = try await runtime.generate(request, receive: { _ in throw SinkFailure.intentional })
      throw TextModelError.invalidResponse
    } catch SinkFailure.intentional {}
    let sinkCleared = await runtime.prefixCacheStatus().tokens == 0
    let cancelled = Task {
      try await runtime.generate(
        request,
        receive: { _ in
          withUnsafeCurrentTask { $0?.cancel() }
        })
    }
    do {
      _ = try await cancelled.value
      throw TextModelError.invalidResponse
    } catch is CancellationError {}
    let cancellationCleared = await runtime.prefixCacheStatus().tokens == 0
    let recovery = try await runtime.generate(request, receive: { _ in })
    let status = await runtime.prefixCacheStatus()
    let release = TextInferenceRequest(
      configuration: request.configuration, generation: .releasingSession(sessionID))
    _ = try await runtime.generate(release, receive: { _ in })
    let result = Result(
      sinkFailureCleared: sinkCleared, cancellationCleared: cancellationCleared,
      recoveryRebuilt: recovery.metrics?.cachedPromptTokens == 0,
      snapshot: status, released: await runtime.prefixCacheStatus(), memory: Memory.snapshot())
    try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(result) + Data([10]))
  }
}
