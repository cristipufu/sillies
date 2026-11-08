import Foundation
import MLX

final class WoofDecoderTransformer {
  private struct Normalization {
    let weight: MLXArray
    let bias: MLXArray
  }
  private struct Layer {
    let attentionNorm: Normalization
    let feedForwardNorm: Normalization
    let queryKeyValue: WoofLinear
    let attentionOutput: WoofLinear
    let feedForwardInput: WoofLinear
    let feedForwardOutput: WoofLinear
  }

  private let configuration: WoofConfiguration.Decoder.Attention
  private let projection: WoofLinear
  private let layers: [Layer]
  private let rotary: WoofRotaryEmbedding
  private var caches: [WoofAttentionCache]
  private var dimensions: Int { configuration.heads * configuration.headDimensions }

  init(configuration: WoofConfiguration.Decoder, weights: WoofWeights, latentDimensions: Int)
    throws
  {
    self.configuration = configuration.attention
    let dimensions = configuration.attention.heads * configuration.attention.headDimensions
    projection = try WoofLinear(
      weight: weights.tensor(configuration.input.weight),
      bias: weights.tensor(configuration.input.bias))
    try projection.validate(input: latentDimensions, output: dimensions)
    let frequencies = try weights.tensor(
      configuration.inverseFrequencies, shape: [configuration.attention.headDimensions / 2])
    rotary = WoofRotaryEmbedding(
      frequencies: frequencies, positions: WoofConfiguration.maximumContext)
    layers = try configuration.layers.map { parameters in
      let attention = try WoofLinear(weight: weights.tensor(parameters.queryKeyValue))
      let output = try WoofLinear(weight: weights.tensor(parameters.attentionOutput))
      let first = try WoofLinear(weight: weights.tensor(parameters.feedForwardInput))
      let second = try WoofLinear(weight: weights.tensor(parameters.feedForwardOutput))
      try attention.validate(input: dimensions, output: dimensions * 3)
      try output.validate(input: dimensions, output: dimensions)
      try first.validate(input: dimensions, output: second.inputDimensions)
      try second.validate(input: first.outputDimensions, output: dimensions)
      func normalization(_ parameters: WoofAffineParameters) throws -> Normalization {
        let weight = try weights.tensor(parameters.weight)
        let bias = try weights.tensor(parameters.bias)
        guard weight.shape == [dimensions], bias.shape == [dimensions] else {
          throw WoofModelError.invalidConfiguration
        }
        eval(weight, bias)
        return Normalization(weight: weight, bias: bias)
      }
      return try Layer(
        attentionNorm: normalization(parameters.attentionNorm),
        feedForwardNorm: normalization(parameters.feedForwardNorm),
        queryKeyValue: attention, attentionOutput: output,
        feedForwardInput: first, feedForwardOutput: second)
    }
    caches = layers.map { _ in WoofAttentionCache() }
  }

  func reset() { caches = layers.map { _ in WoofAttentionCache() } }

  func callAsFunction(_ latents: MLXArray) throws -> MLXArray {
    guard latents.ndim == 2, latents.dim(1) == projection.inputDimensions,
      latents.dim(0) > 0,
      latents.dim(0) <= WoofConfiguration.maximumContext - (caches.first?.offset ?? 0)
    else { throw WoofModelError.invalidConfiguration }
    var hidden = projection(latents)
    for index in layers.indices {
      try Task.checkCancellation()
      let layer = layers[index]
      hidden =
        hidden
        + attention(normalize(hidden, layer.attentionNorm), layer: layer, cache: &caches[index])
      let activation = layer.feedForwardInput(normalize(hidden, layer.feedForwardNorm))
      let gaussian = 0.5 * activation * (1 + erf(activation * Float(1 / sqrt(2.0))))
      hidden = hidden + layer.feedForwardOutput(gaussian)
    }
    eval(hidden)
    for cache in caches { cache.materialize() }
    return hidden
  }

  private func normalize(_ hidden: MLXArray, _ normalization: Normalization) -> MLXArray {
    MLXFast.layerNorm(
      hidden, weight: normalization.weight, bias: normalization.bias, eps: configuration.epsilon)
  }

  private func attention(_ input: MLXArray, layer: Layer, cache: inout WoofAttentionCache)
    -> MLXArray
  {
    let length = input.dim(0)
    let projected = layer.queryKeyValue(input)
      .reshaped(length, 3, configuration.heads, configuration.headDimensions).transposed(1, 2, 0, 3)
    let queries = rotary.apply(projected[0].expandedDimensions(axis: 0), offset: cache.offset)
    let keys = rotary.apply(projected[1].expandedDimensions(axis: 0), offset: cache.offset)
    let attended = cache.attend(
      queries: queries, newKeys: keys, newValues: projected[2].expandedDimensions(axis: 0),
      window: configuration.window)
    return layer.attentionOutput(attended.transposed(0, 2, 1, 3).reshaped(length, dimensions))
  }
}
