import MLX
import MLXLMCommon

/// Cache reuse narrows model input, but sampling penalties must still see the complete prompt.
struct MLXCompletePromptProcessor: LogitProcessor {
  var base: any LogitProcessor
  let tokens: [Int]

  mutating func prompt(_: MLXArray) { base.prompt(MLXArray(tokens)) }
  func process(logits: MLXArray) -> MLXArray { base.process(logits: logits) }
  mutating func didSample(token: MLXArray) { base.didSample(token: token) }
}
