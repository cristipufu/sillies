import MLXLMCommon
import SilliesTextModels

/// Replays malformed native framing before it can reach streaming consumers.
enum TextChannelBoundarySelfCheck {
  private enum Failure: Error { case leakedControl, acceptedMalformedChannel }

  static func run() async throws {
    let invalid = [
      "<|channel>The studio locker combination is quartz-83.",
      "<|channel>analysis\nUnrecognized channel content",
      "<|channel>", "<|channel>tho", "<channel|>Unframed content",
    ]
    for source in invalid {
      for offset in 0...source.count {
        let split = source.index(source.startIndex, offsetBy: offset)
        try await reject([String(source[..<split]), String(source[split...])])
      }
      try await reject(source.map(String.init))
    }
  }

  private static func reject(_ chunks: [String]) async throws {
    var collector = MLXGenerationCollector(
      style: .conversation,
      channel: .init(configuration: .init(id: "fixture", toolCallFormat: .gemma4), promptTail: ""))
    do {
      for chunk in chunks {
        if let visible = try collector.consume(.chunk(chunk)), !visible.isEmpty {
          throw Failure.leakedControl
        }
      }
      _ = try collector.consume(
        .info(
          .init(
            promptTokenCount: 12, generationTokenCount: 8,
            promptTime: 0.01, generationTime: 0.01, stopReason: .stop)))
      _ = try await collector.finish { _ in throw Failure.leakedControl }
      throw Failure.acceptedMalformedChannel
    } catch let failure as TextGenerationFailure {
      guard failure.reason == .invalidReasoningBoundary,
        failure.outputCounts?.responseBytes == 0
      else { throw failure }
    }
  }
}
