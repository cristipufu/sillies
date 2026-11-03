import MLX
import MLXLMCommon

/// Applies checkpoint-declared exclusions before sampling, after the configured penalty processor.
struct MLXSuppressedTokens: LogitProcessor {
  let tokens: [Int32]

  mutating func prompt(_ prompt: MLXArray) {}
  mutating func didSample(token: MLXArray) {}

  func process(logits: MLXArray) -> MLXArray {
    guard !tokens.isEmpty else { return logits }
    var indices = MLXArray(tokens)
    if logits.ndim > 1 {
      indices = indices.reshaped(Array(repeating: 1, count: logits.ndim - 1) + [tokens.count])
    }
    return putAlong(
      logits, indices, values: MLXArray(-Float.infinity).asType(logits.dtype), axis: -1)
  }
}

extension CheckpointGenerationConstraints {
  var components: GenerationComponents {
    guard !suppressedTokens.isEmpty else { return .init() }
    return .init(logitProcessorFactory: { MLXSuppressedTokens(tokens: suppressedTokens) })
  }
}
