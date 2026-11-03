import Foundation
import MLX
import MLXLMCommon
import SilliesTextModels

/// Accumulates one bounded generation while keeping native tool and reasoning channels separate.
struct MLXGenerationCollector {
  private let style: TextGenerationStyle
  private var channel: MLXReasoningChannel
  private var text = ""
  private var calls: [TextGenerationOutput.Call] = []
  private var metrics: TextGenerationMetrics?
  private var batch = TextStreamBatch()

  init(style: TextGenerationStyle, channel: MLXReasoningChannel) {
    self.style = style
    self.channel = channel
  }

  mutating func consume(_ event: Generation) throws -> String? {
    switch event {
    case .chunk(let chunk):
      do { return try append(channel.append(chunk)) } catch is ReasoningResponseBoundary.Failure {
        throw failure(.invalidReasoningBoundary)
      }
    case .info(let info):
      metrics = .init(
        tokens: .init(
          processedPrompt: info.promptTokenCount,
          cachedPrompt: info.cachedPromptTokenCount, generated: info.generationTokenCount),
        timing: .init(prompt: info.promptTime, generation: info.generateTime),
        peakDeviceMemoryBytes: Memory.peakMemory)
      switch info.stopReason {
      case .stop: break
      case .length: throw failure(.outputTokenLimit)
      case .cancelled: throw CancellationError()
      }
    case .toolCall(let call):
      calls.append(
        .init(
          id: call.id ?? UUID().uuidString, name: call.function.name,
          arguments: try JSONEncoder().encode(call.function.arguments)))
    case .rejectedToolCall(let rejection):
      throw TextGenerationFailure(
        reason: .rejectedToolCall, metrics: metrics,
        toolRejection: .init(rejection), outputCounts: outputCounts)
    }
    return nil
  }

  mutating func finish(receive: @escaping TextDeltaSink) async throws -> TextGenerationOutput {
    guard metrics != nil else { throw failure(.missingCompletion) }
    do {
      if let delta = try append(channel.finish()) { try await receive(delta) }
    } catch is ReasoningResponseBoundary.Failure {
      throw failure(.invalidReasoningBoundary)
    }
    if let delta = batch.flush() { try await receive(delta) }
    return .init(
      text: text.trimmingCharacters(in: .whitespacesAndNewlines), calls: calls, metrics: metrics,
      reasoningContent: calls.isEmpty || channel.content.isEmpty ? nil : channel.content)
  }

  private mutating func append(_ delta: String) throws -> String? {
    text += delta
    guard text.utf8.count + channel.content.utf8.count <= TextInferenceWire.maximumMessageBytes / 2
    else { throw failure(.responseSizeLimit) }
    if style == .conversation, TextRepetitionGuard.containsLoop(text) {
      throw TextModelError.repetitiveResponse
    }
    return batch.append(delta)
  }

  private var outputCounts: TextGenerationFailure.OutputCounts {
    .init(
      responseBytes: text.utf8.count, reasoningBytes: channel.content.utf8.count,
      acceptedToolCalls: calls.count)
  }

  private func failure(_ reason: TextGenerationFailure.Reason) -> TextGenerationFailure {
    .init(reason: reason, metrics: metrics, outputCounts: outputCounts)
  }
}
