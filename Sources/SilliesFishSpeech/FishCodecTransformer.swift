import Foundation
import MLX

struct FishCodecTransformer {
  private static let layerCount = 8
  private static let headCount = 16
  private static let headDimensions = 64
  private static let attentionWindow = 128
  private static let epsilon: Float = 1e-5
  private static let prefix = "quantizer.post_module"
  let weights: FishWeights

  func apply(_ input: MLXArray) throws -> MLXArray {
    var hidden = input.transposed(0, 2, 1)
    let length = hidden.dim(1)
    let rotary = FishRotaryEmbedding(
      headDimensions: Self.headDimensions, positions: length, base: 10_000, precision: .codec)
    let row = arange(length).expandedDimensions(axis: 1)
    let column = arange(length).expandedDimensions(axis: 0)
    let mask = ((column .<= row) .&& (column .>= (row - Self.attentionWindow + 1)))
      .reshaped(1, 1, length, length)
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
    let attended = try MLXFast.scaledDotProductAttention(
      queries: rotary.apply(query, offset: 0), keys: rotary.apply(key, offset: 0), values: value,
      scale: 1 / sqrt(Float(Self.headDimensions)), mask: .array(mask)
    )
    .transposed(0, 2, 1, 3).reshaped(1, length, dimensions)
    return try weights.linear(attended, at: path + ".wo")
  }
}
