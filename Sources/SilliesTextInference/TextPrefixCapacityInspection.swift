import Foundation
import MLX
import SilliesTextModels

/// Replay a bounded sequence through the real runtime, observing retained state after every turn.
enum TextPrefixCapacityInspection {
  private static let maximumRequests = 48
  private static let maximumBatchBytes = maximumRequests * TextInferenceWire.maximumMessageBytes
  private struct Result: Encodable {
    let index: Int
    let text: String
    let cachedTokens: Int
    let snapshot: MLXPrefixSnapshot.Status
    let memory: Memory.Snapshot
  }

  static func run(requestURL: URL) async throws {
    let requests = try TextInferenceJSON.read(
      [TextInferenceRequest].self, from: requestURL,
      maximumBytes: maximumBatchBytes)
    guard !requests.isEmpty, requests.count <= maximumRequests else {
      throw TextModelError.invalidResponse
    }
    let runtime = MLXTextRuntime()
    for (index, request) in requests.enumerated() {
      let output = try await runtime.generate(request, receive: { _ in })
      let result = Result(
        index: index, text: output.text,
        cachedTokens: output.metrics?.cachedPromptTokens ?? 0,
        snapshot: await runtime.prefixCacheStatus(), memory: Memory.snapshot())
      try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(result) + Data([10]))
    }
  }
}
