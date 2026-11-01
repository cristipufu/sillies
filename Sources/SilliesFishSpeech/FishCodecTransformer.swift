import Foundation
import MLX

final class FishCodecTransformer {
  private static let layerCount = 8
  private static let headCount = 16
  private static let headDimensions = 64
  private static let attentionWindow = 128
  private static let epsilon: Float = 1e-5
  private static let prefix = "quantizer.post_module"
  let weights: FishWeights
  private var position = 0
  private var keys: [String: MLXArray] = [:]
  private var values: [String: MLXArray] = [:]
  init(weights: FishWeights) { self.weights = weights }
  func reset() {
    position = 0
    keys.removeAll()
    values.removeAll()
  }

  func apply(_ input: MLXArray) throws -> MLXArray {
    var hidden = input.transposed(0, 2, 1)
    let length = hidden.dim(1)
    guard length > 0, position <= FishConfiguration.maximumAudioFrames - length else {
      throw FishError.generationLimit
    }
    let rotary = FishRotaryEmbedding(
      headDimensions: Self.headDimensions, positions: position + length, base: 10_000,
      precision: .codec)
    let retained = min(position, Self.attentionWindow)
    let row = arange(position, position + length).expandedDimensions(axis: 1)
    let column = arange(position - retained, position + length).expandedDimensions(axis: 0)
    let mask = ((column .<= row) .&& (column .>= (row - Self.attentionWindow + 1)))
      .reshaped(1, 1, length, retained + length)
    for index in 0..<Self.layerCount {
      try Task.checkCancellation()
      let path = Self.prefix + ".layers.\(index)"
      let normalized = try weights.normalized(
        hidden, at: path + ".attention_norm", epsilon: Self.epsilon)
      let attention = try attend(normalized, at: path + ".attention", rotary: rotary, mask: mask)
      hidden =
        try hidden + attention
        * weights.vector(path + ".attention_layer_scale.gamma", count: hidden.dim(2))
      let feedInput = try weights.normalized(hidden, at: path + ".ffn_norm", epsilon: Self.epsilon)
      let feedOutput = try weights.gatedFeedForward(feedInput, at: path + ".feed_forward")
      hidden =
        try hidden + feedOutput
        * weights.vector(path + ".ffn_layer_scale.gamma", count: hidden.dim(2))
    }
    position += length
    return try weights.normalized(hidden, at: Self.prefix + ".norm", epsilon: Self.epsilon)
      .transposed(0, 2, 1)
  }

  private func attend(
    _ input: MLXArray, at path: String, rotary: FishRotaryEmbedding, mask: MLXArray
  ) throws -> MLXArray {
    let dimensions = Self.headCount * Self.headDimensions
    let length = input.dim(1)
    let projection = try weights.linear(input, at: path + ".wqkv")
    guard projection.dim(2) == dimensions * 3 else { throw FishError.invalidTensor(path) }
    let query = projection[0..., 0..., 0..<dimensions]
      .reshaped(1, length, Self.headCount, Self.headDimensions).transposed(0, 2, 1, 3)
    let key = projection[0..., 0..., dimensions..<(2 * dimensions)]
      .reshaped(1, length, Self.headCount, Self.headDimensions).transposed(0, 2, 1, 3)
    let value = projection[0..., 0..., (2 * dimensions)...]
      .reshaped(1, length, Self.headCount, Self.headDimensions).transposed(0, 2, 1, 3)
    let rotatedKey = try rotary.apply(key, offset: position)
    let allKeys = keys[path].map { concatenated([$0, rotatedKey], axis: 2) } ?? rotatedKey
    let allValues = values[path].map { concatenated([$0, value], axis: 2) } ?? value
    let start = max(0, allKeys.dim(2) - Self.attentionWindow)
    let retainedKeys = allKeys[0..., 0..., start..., 0...]
    let retainedValues = allValues[0..., 0..., start..., 0...]
    eval(retainedKeys, retainedValues)
    keys[path] = retainedKeys
    values[path] = retainedValues
    let attended = try MLXFast.scaledDotProductAttention(
      queries: rotary.apply(query, offset: position), keys: allKeys, values: allValues,
      scale: 1 / sqrt(Float(Self.headDimensions)), mask: .array(mask)
    )
    .transposed(0, 2, 1, 3).reshaped(1, length, dimensions)
    return try weights.linear(attended, at: path + ".wo")
  }
}
