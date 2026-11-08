import Foundation
import MLX

final class WoofSpeechTransformer {
  private struct Layer {
    let queryKeyValue: WoofLinear
    let attentionOutput: WoofLinear
    let gateUp: WoofLinear
    let down: WoofLinear
  }

  private let configuration: WoofConfiguration.Transformer
  private let layers: [Layer]
  private let rotary: WoofRotaryEmbedding
  private let unitScale: MLXArray
  private var caches: [WoofAttentionCache]

  init(configuration: WoofConfiguration.Speech, weights: WoofWeights) throws {
    self.configuration = configuration.transformer
    let dimensions = configuration.transformer.dimensions
    let feedForward = configuration.transformer.feedForwardDimensions
    layers = try configuration.layers.map { parameters in
      let layer = try Layer(
        queryKeyValue: weights.linear(parameters.queryKeyValue),
        attentionOutput: weights.linear(parameters.attentionOutput),
        gateUp: weights.linear(parameters.gateUp), down: weights.linear(parameters.down))
      try layer.queryKeyValue.validate(input: dimensions, output: 3 * dimensions)
      try layer.attentionOutput.validate(input: dimensions, output: dimensions)
      try layer.gateUp.validate(input: dimensions, output: 2 * feedForward)
      try layer.down.validate(input: feedForward, output: dimensions)
      return layer
    }
    caches = layers.map { _ in WoofAttentionCache() }
    unitScale = MLXArray.ones([dimensions])
    let headDimensions = dimensions / configuration.transformer.heads
    let frequencies =
      1
      / pow(
        MLXArray(configuration.transformer.rotaryBase),
        arange(0, headDimensions, step: 2).asType(.float32) / Float(headDimensions))
    rotary = WoofRotaryEmbedding(
      frequencies: frequencies, positions: WoofConfiguration.maximumContext)
  }

  func reset() { caches = layers.map { _ in WoofAttentionCache() } }

  func callAsFunction(_ input: MLXArray) throws -> MLXArray {
    guard input.ndim == 2, input.dim(1) == configuration.dimensions, input.dim(0) > 0,
      input.dim(0) <= WoofConfiguration.maximumContext - (caches.first?.offset ?? 0)
    else { throw WoofModelError.invalidConfiguration }
    var hidden = input
    for index in layers.indices {
      try Task.checkCancellation()
      hidden = hidden + attention(normalized(hidden), layer: layers[index], cache: &caches[index])
      let gates = layers[index].gateUp(normalized(hidden))
      let gate = gates[0..., ..<configuration.feedForwardDimensions]
      let up = gates[0..., configuration.feedForwardDimensions...]
      hidden = hidden + layers[index].down(gate * sigmoid(gate) * up)
    }
    eval(hidden)
    for cache in caches { cache.materialize() }
    return hidden
  }

  private func normalized(_ input: MLXArray) -> MLXArray {
    MLXFast.rmsNorm(input, weight: unitScale, eps: Float.ulpOfOne)
  }

  private func attention(_ input: MLXArray, layer: Layer, cache: inout WoofAttentionCache)
    -> MLXArray
  {
    let headDimensions = configuration.dimensions / configuration.heads
    let length = input.dim(0)
    let projection = layer.queryKeyValue(input)
      .reshaped(length, 3, configuration.heads, headDimensions).transposed(1, 2, 0, 3)
    let queries = rotary.apply(projection[0].expandedDimensions(axis: 0), offset: cache.offset)
    let keys = rotary.apply(projection[1].expandedDimensions(axis: 0), offset: cache.offset)
    let values = projection[2].expandedDimensions(axis: 0)
    let attended = cache.attend(queries: queries, newKeys: keys, newValues: values)
      .transposed(0, 2, 1, 3).reshaped(length, configuration.dimensions)
    return layer.attentionOutput(attended)
  }
}
