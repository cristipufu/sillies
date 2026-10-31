import Foundation
import MLX

/// A single owner for each attention cache; the fast decoder gets a fresh cache per audio frame.
final class FishTransformer {
  private struct AttentionCache {
    var keys: MLXArray?
    var values: MLXArray?
    var count: Int { keys?.dim(2) ?? 0 }

    mutating func append(keys newKeys: MLXArray, values newValues: MLXArray) -> (MLXArray, MLXArray)
    {
      let combinedKeys = keys.map { concatenated([$0, newKeys], axis: 2) } ?? newKeys
      let combinedValues = values.map { concatenated([$0, newValues], axis: 2) } ?? newValues
      keys = combinedKeys
      values = combinedValues
      return (combinedKeys, combinedValues)
    }
  }

  private let weights: FishWeights
  private let configuration: FishConfiguration.Transformer
  private let rotary: FishRotaryEmbedding
  private let prefix: String
  private var caches: [AttentionCache]

  init(weights: FishWeights, configuration: FishConfiguration.Transformer, prefix: String) {
    self.weights = weights
    self.configuration = configuration
    self.prefix = prefix
    rotary = FishRotaryEmbedding(
      headDimensions: configuration.headDim, positions: FishConfiguration.maximumContextTokens,
      base: configuration.ropeBase, precision: .speech)
    caches = Array(repeating: AttentionCache(), count: configuration.nLayer)
  }

  func reset() { caches = Array(repeating: AttentionCache(), count: configuration.nLayer) }

  func apply(_ input: MLXArray) throws -> MLXArray {
    var hidden = input
    for index in caches.indices {
      try Task.checkCancellation()
      let path = prefix + "layers.\(index)"
      let normalized = try weights.normalized(
        hidden, at: path + ".attention_norm", epsilon: configuration.normEps)
      hidden = try hidden + attention(normalized, at: path + ".attention", cache: &caches[index])
      let feedInput = try weights.normalized(
        hidden, at: path + ".ffn_norm", epsilon: configuration.normEps)
      hidden = try hidden + weights.gatedFeedForward(feedInput, at: path + ".feed_forward")
    }
    return try weights.normalized(hidden, at: prefix + "norm", epsilon: configuration.normEps)
  }

  private func attention(_ input: MLXArray, at path: String, cache: inout AttentionCache) throws
    -> MLXArray
  {
    let headDimensions = configuration.headDim
    let querySize = configuration.nHead * headDimensions
    let keySize = configuration.nLocalHeads * headDimensions
    let length = input.dim(1)
    let projection = try weights.linear(input, at: path + ".wqkv")
    guard projection.dim(-1) == querySize + 2 * keySize else { throw FishError.invalidTensor(path) }
    var queries = projection[0..., 0..., 0..<querySize]
      .reshaped(1, length, configuration.nHead, headDimensions).transposed(0, 2, 1, 3)
    var keys = projection[0..., 0..., querySize..<(querySize + keySize)]
      .reshaped(1, length, configuration.nLocalHeads, headDimensions).transposed(0, 2, 1, 3)
    var values = projection[0..., 0..., (querySize + keySize)...]
      .reshaped(1, length, configuration.nLocalHeads, headDimensions).transposed(0, 2, 1, 3)
    if configuration.attentionQkNorm {
      queries = try weights.normalized(
        queries, at: path + ".q_norm", epsilon: configuration.normEps)
      keys = try weights.normalized(keys, at: path + ".k_norm", epsilon: configuration.normEps)
    }
    queries = try rotary.apply(queries, offset: cache.count)
    keys = try rotary.apply(keys, offset: cache.count)
    (keys, values) = cache.append(keys: keys, values: values)
    let attended = MLXFast.scaledDotProductAttention(
      queries: queries, keys: keys, values: values,
      scale: 1 / sqrt(Float(headDimensions)), mask: length > 1 ? .causal : .none
    )
    .transposed(0, 2, 1, 3).reshaped(1, length, querySize)
    return try weights.linear(attended, at: path + ".wo")
  }
}
