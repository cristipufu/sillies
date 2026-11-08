import Foundation
import MLX
import SilliesTTS

/// Text and speech stacks use the same Qwen2 blocks, with independent per-utterance caches.
struct VibeVoiceTransformer {
  struct Stack {
    let path: String
    let layerCount: Int
    var finalNorm: MLXArray?
  }
  struct Cache {
    var keys: MLXArray
    var values: MLXArray
    var count: Int { keys.dim(2) }
    func materialize() { eval(keys, values) }
  }

  private struct Layer {
    let attentionNorm: MLXArray
    let feedForwardNorm: MLXArray
    let query: VibeVoiceLinear
    let key: VibeVoiceLinear
    let value: VibeVoiceLinear
    let output: VibeVoiceLinear
    let gate: VibeVoiceLinear
    let up: VibeVoiceLinear
    let down: VibeVoiceLinear
  }

  private let configuration: VibeVoiceConfiguration.Transformer
  private let layers: [Layer]
  private let finalNorm: MLXArray?

  init(
    configuration: VibeVoiceConfiguration.Transformer, weights: VibeVoiceWeights, stack: Stack
  ) throws {
    self.configuration = configuration
    finalNorm = stack.finalNorm
    let dimensions = configuration.dimensions
    let keyValueDimensions = configuration.keyValueHeads * configuration.headDimensions
    layers = try (0..<stack.layerCount).map { index in
      let layer = "\(stack.path).layers.\(index)"
      return try Layer(
        attentionNorm: weights.tensor(layer + ".input_layernorm.weight", shape: [dimensions]),
        feedForwardNorm: weights.tensor(
          layer + ".post_attention_layernorm.weight", shape: [dimensions]),
        query: weights.linear(layer + ".self_attn.q_proj", input: dimensions, output: dimensions),
        key: weights.linear(
          layer + ".self_attn.k_proj", input: dimensions, output: keyValueDimensions),
        value: weights.linear(
          layer + ".self_attn.v_proj", input: dimensions, output: keyValueDimensions),
        output: weights.linear(layer + ".self_attn.o_proj", input: dimensions, output: dimensions),
        gate: weights.linear(
          layer + ".mlp.gate_proj", input: dimensions, output: configuration.feedForwardDimensions),
        up: weights.linear(
          layer + ".mlp.up_proj", input: dimensions, output: configuration.feedForwardDimensions),
        down: weights.linear(
          layer + ".mlp.down_proj", input: configuration.feedForwardDimensions, output: dimensions))
    }
  }

  func callAsFunction(_ input: MLXArray, caches: inout [Cache]) throws -> MLXArray {
    guard input.ndim == 2, input.dim(0) > 0, input.dim(1) == configuration.dimensions,
      caches.count == layers.count
    else { throw VibeVoiceError.invalidTensor("transformer input") }
    guard caches.allSatisfy({ $0.count <= configuration.maximumContext - input.dim(0) }) else {
      throw TTSError.invalidRequest
    }
    var hidden = input
    for index in layers.indices {
      try Task.checkCancellation()
      let layer = layers[index]
      let normalized = MLXFast.rmsNorm(
        hidden, weight: layer.attentionNorm, eps: configuration.normalizationEpsilon)
      hidden = hidden + attend(normalized, layer: layer, cache: &caches[index])
      let feedForward = MLXFast.rmsNorm(
        hidden, weight: layer.feedForwardNorm, eps: configuration.normalizationEpsilon)
      let gate = layer.gate(feedForward)
      hidden = hidden + layer.down(gate * sigmoid(gate) * layer.up(feedForward))
    }
    if let finalNorm {
      hidden = MLXFast.rmsNorm(hidden, weight: finalNorm, eps: configuration.normalizationEpsilon)
    }
    eval(hidden)
    for cache in caches { cache.materialize() }
    return hidden
  }

  private func attend(_ input: MLXArray, layer: Layer, cache: inout Cache) -> MLXArray {
    let length = input.dim(0)
    let offset = cache.count
    let queries = rotated(layer.query(input), heads: configuration.attentionHeads, offset: offset)
    let keys = rotated(layer.key(input), heads: configuration.keyValueHeads, offset: offset)
    let values = layer.value(input).reshaped(
      1, length, configuration.keyValueHeads, configuration.headDimensions
    ).transposed(0, 2, 1, 3)
    cache.keys = concatenated([cache.keys, keys], axis: 2)
    cache.values = concatenated([cache.values, values], axis: 2)
    let queryPositions = (arange(length) + offset).expandedDimensions(axis: 1)
    let keyPositions = arange(cache.count).expandedDimensions(axis: 0)
    let mask = MLX.where(
      keyPositions .<= queryPositions, MLXArray(Float(0)), MLXArray(-Float.infinity))
    let attended = MLXFast.scaledDotProductAttention(
      queries: queries, keys: cache.keys, values: cache.values,
      scale: 1 / sqrt(Float(configuration.headDimensions)), mask: mask)
    return layer.output(attended.transposed(0, 2, 1, 3).reshaped(length, configuration.dimensions))
  }

  private func rotated(_ input: MLXArray, heads: Int, offset: Int) -> MLXArray {
    let length = input.dim(0)
    let shaped = input.reshaped(length, heads, configuration.headDimensions).transposed(1, 0, 2)
    return MLXFast.RoPE(
      shaped, dimensions: configuration.headDimensions, traditional: false,
      base: configuration.rotaryBase, scale: 1, offset: offset
    ).expandedDimensions(axis: 0)
  }
}
