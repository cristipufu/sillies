import Foundation
import SilliesTextModels

/// Content-free stage receipts survive a process deadline, when the unfinished turn cannot be saved.
enum BenchmarkInferenceStage {
  private struct Receipt: Encodable {
    let event: String
    let style: TextGenerationStyle
    let messageCount: Int
    let toolCount: Int
    let maximumTokens: Int
    let seconds: Double?
    let metrics: TextGenerationMetrics?
    let failure: TextGenerationFailure.Reason?
  }

  static func started(_ request: TextGenerationRequest) throws {
    try write(request, event: "generationStarted", result: nil)
  }

  static func finished(_ generation: BenchmarkGeneration) throws {
    try write(generation.request, event: "generationFinished", result: generation)
  }

  private static func write(
    _ request: TextGenerationRequest, event: String, result: BenchmarkGeneration?
  ) throws {
    let receipt = Receipt(
      event: event, style: request.style, messageCount: request.messages.count,
      toolCount: request.tools.count, maximumTokens: request.maximumTokens,
      seconds: result?.seconds, metrics: result?.output?.metrics ?? result?.failure?.metrics,
      failure: result?.failure?.reason)
    var data = try JSONEncoder().encode(receipt)
    data.append(contentsOf: "\n".utf8)
    try FileHandle.standardError.write(contentsOf: data)
  }
}
