import MLX

struct WoofFlowHead {
  private struct Block {
    let input: WoofLinear
    let output: WoofLinear
  }
  private static let normalizationEpsilon: Float = 1e-5
  private let conditioning: WoofLinear
  private let modulation: WoofLinear
  private let input: WoofLinear
  private let output: WoofLinear
  private let blocks: [Block]
  private let dimensions: Int
  private let unitScale: MLXArray

  init(configuration: WoofConfiguration.Speech, weights: WoofWeights) throws {
    let dimensions = configuration.transformer.flowDimensions
    self.dimensions = dimensions
    conditioning = try weights.linear(configuration.conditioning)
    modulation = try weights.linear(configuration.adaptiveModulation)
    input = try weights.linear(configuration.flowInput)
    output = try weights.linear(configuration.flowOutput)
    unitScale = MLXArray.ones([configuration.transformer.dimensions])
    try conditioning.validate(input: configuration.transformer.dimensions, output: dimensions + 1)
    try modulation.validate(
      input: dimensions, output: dimensions * (3 * configuration.transformer.flowDepth + 2))
    try input.validate(input: configuration.transformer.latentDimensions, output: dimensions)
    try output.validate(input: dimensions, output: configuration.transformer.latentDimensions)
    blocks = try configuration.flowBlocks.map { parameters in
      let first = try weights.linear(parameters.input)
      let second = try weights.linear(parameters.output)
      guard first.inputDimensions == dimensions, second.outputDimensions == dimensions,
        first.outputDimensions == second.inputDimensions
      else { throw WoofModelError.invalidConfiguration }
      return Block(input: first, output: second)
    }
  }

  func condition(_ hidden: MLXArray) -> (state: MLXArray, endLogit: Float) {
    let result = conditioning(MLXFast.rmsNorm(hidden, weight: unitScale, eps: Float.ulpOfOne))
    let state = result[..<dimensions]
    return (state * sigmoid(state), result[dimensions].item(Float.self))
  }

  func latent(condition: MLXArray, noise: MLXArray) -> MLXArray {
    let parameters = modulation(condition)
    var hidden = input(noise)
    for (index, block) in blocks.enumerated() {
      let start = index * 3 * dimensions
      let adjusted = modulate(hidden, parameters: parameters, offset: start)
      let activation = block.input(adjusted)
      let residual = block.output(activation * sigmoid(activation))
      hidden = hidden + parameters[(start + 2 * dimensions)..<(start + 3 * dimensions)] * residual
    }
    return noise
      + output(modulate(hidden, parameters: parameters, offset: blocks.count * 3 * dimensions))
  }

  private func modulate(_ hidden: MLXArray, parameters: MLXArray, offset: Int) -> MLXArray {
    let normalized = MLXFast.layerNorm(hidden, eps: Self.normalizationEpsilon)
    return parameters[offset..<(offset + dimensions)]
      + normalized * parameters[(offset + dimensions)..<(offset + 2 * dimensions)]
  }
}
