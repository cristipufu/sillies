import Foundation
import MLXLMCommon
import SilliesTextModels

enum TextGenerationFailureSelfCheck {
  static func run() async throws {
    try tokenLimit()
    try rejectedCalls()
    var collector = makeCollector()
    do {
      _ = try await collector.finish(receive: { _ in })
      throw TextModelError.invalidResponse
    } catch let failure as TextGenerationFailure {
      guard failure.reason == .missingCompletion else { throw failure }
    }
  }

  private static func tokenLimit() throws {
    var collector = makeCollector()
    do {
      _ = try collector.consume(
        .info(
          .init(
            promptTokenCount: 800, generationTokenCount: 240,
            promptTime: 0.2, generationTime: 2, stopReason: .length)))
      throw TextModelError.invalidResponse
    } catch let failure as TextGenerationFailure {
      guard failure.reason == .outputTokenLimit, failure.metrics?.generatedTokens == 240,
        failure.metrics?.processedPromptTokens == 800
      else { throw failure }
    }
  }

  private static func rejectedCalls() throws {
    for reason in RejectedToolCall.Reason.allCases {
      var collector = makeCollector()
      do {
        _ = try collector.consume(
          .rejectedToolCall(
            .init(
              reason: reason, format: .gemma4, toolName: "synthetic-secret",
              rawText: "synthetic-secret")))
        throw TextModelError.invalidResponse
      } catch let failure as TextGenerationFailure {
        let encoded = String(decoding: try JSONEncoder().encode(failure), as: UTF8.self)
        guard failure.reason == .rejectedToolCall, failure.toolRejection != nil,
          !encoded.contains("synthetic-secret")
        else { throw failure }
      }
    }
  }

  private static func makeCollector() -> MLXGenerationCollector {
    .init(style: .conversation, channel: .init(configuration: .init(id: "fixture"), promptTail: ""))
  }
}
