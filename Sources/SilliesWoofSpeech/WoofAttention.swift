import Foundation
import MLX

/// A cache belongs to one utterance. Decoder caches retain only their declared attention window.
struct WoofAttentionCache {
  private var keys: MLXArray?
  private var values: MLXArray?
  private(set) var offset = 0

  mutating func attend(
    queries: MLXArray, newKeys: MLXArray, newValues: MLXArray, window: Int? = nil
  ) -> MLXArray {
    let combinedKeys = keys.map { concatenated([$0, newKeys], axis: 2) } ?? newKeys
    let combinedValues = values.map { concatenated([$0, newValues], axis: 2) } ?? newValues
    let queryCount = queries.dim(2)
    let keyCount = combinedKeys.dim(2)
    let mask: MLXFast.ScaledDotProductAttentionMaskMode
    if let window {
      let queryPositions = arange(keyCount - queryCount, keyCount).expandedDimensions(axis: 1)
      let keyPositions = arange(keyCount).expandedDimensions(axis: 0)
      mask = .array((keyPositions .<= queryPositions) .&& (keyPositions .> queryPositions - window))
    } else {
      mask = queryCount > 1 ? .causal : .none
    }
    let output = MLXFast.scaledDotProductAttention(
      queries: queries, keys: combinedKeys, values: combinedValues,
      scale: 1 / sqrt(Float(queries.dim(-1))), mask: mask)
    let retained = min(keyCount, window ?? keyCount)
    keys = combinedKeys[0..., 0..., (keyCount - retained)..., 0...]
    values = combinedValues[0..., 0..., (keyCount - retained)..., 0...]
    offset += queryCount
    return output
  }

  func materialize() {
    if let keys, let values { eval(keys, values) }
  }
}

struct WoofRotaryEmbedding {
  let cosine: MLXArray
  let sine: MLXArray

  init(frequencies: MLXArray, positions: Int) {
    let angles = outer(arange(positions).asType(.float32), frequencies)
    cosine = cos(angles)
    sine = sin(angles)
    eval(cosine, sine)
  }

  func apply(_ input: MLXArray, offset: Int) -> MLXArray {
    let length = input.dim(2)
    let half = input.dim(-1) / 2
    let left = input[0..., 0..., 0..., ..<half]
    let right = input[0..., 0..., 0..., half...]
    let cosine = cosine[offset..<(offset + length)]
    let sine = sine[offset..<(offset + length)]
    return concatenated([left * cosine - right * sine, right * cosine + left * sine], axis: -1)
  }
}
