import Foundation
import MLX

/// Immutable publisher-provided voice state; every utterance starts from fresh cache values.
struct VibeVoicePrompt {
  let text: [VibeVoiceTransformer.Cache]
  let speech: [VibeVoiceTransformer.Cache]
  let negativeSpeech: [VibeVoiceTransformer.Cache]
  let negativeCondition: MLXArray
  private static let maximumVoiceBytes = 16 * 1_024 * 1_024
  private static let maximumPromptTokens = 1_024

  init(url: URL, configuration: VibeVoiceConfiguration) throws {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard (1...Self.maximumVoiceBytes).contains(size) else { throw VibeVoiceError.invalidVoice }
    let tensors = try loadArrays(url: url)
    let dimensions = configuration.transformer
    func caches(_ prefix: String, count: Int) throws -> [VibeVoiceTransformer.Cache] {
      let result = try (0..<count).map { index in
        guard let key = tensors["\(prefix)_key_\(index)"],
          let value = tensors["\(prefix)_value_\(index)"],
          key.ndim == 4, key.shape == value.shape, key.dim(0) == 1,
          key.dim(1) == dimensions.keyValueHeads, key.dim(3) == dimensions.headDimensions,
          (1...Self.maximumPromptTokens).contains(key.dim(2)),
          key.dtype.isFloatingPoint, value.dtype.isFloatingPoint
        else { throw VibeVoiceError.invalidVoice }
        let cache = VibeVoiceTransformer.Cache(
          keys: key.asType(.float32), values: value.asType(.float32))
        cache.materialize()
        return cache
      }
      guard Set(result.map(\.count)).count == 1 else { throw VibeVoiceError.invalidVoice }
      return result
    }
    text = try caches("lm", count: dimensions.layers - configuration.speechLayers)
    speech = try caches("tts_lm", count: configuration.speechLayers)
    negativeSpeech = try caches("neg_tts_lm", count: configuration.speechLayers)
    guard let condition = tensors["neg_tts_lm_hidden"],
      condition.shape == [1, negativeSpeech[0].count, dimensions.dimensions],
      condition.dtype.isFloatingPoint
    else { throw VibeVoiceError.invalidVoice }
    negativeCondition = condition[0, -1].reshaped(1, dimensions.dimensions).asType(.float32)
    eval(negativeCondition)
  }
}
