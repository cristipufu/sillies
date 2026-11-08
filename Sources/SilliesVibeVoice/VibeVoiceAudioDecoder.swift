import Foundation
import MLX

final class VibeVoiceAudioDecoder {
  private struct Block {
    let norm: MLXArray
    let feedForwardNorm: MLXArray
    let mixer: VibeVoiceConvolution
    let mixerScale: MLXArray
    let feedForwardScale: MLXArray
    let input: VibeVoiceLinear
    let output: VibeVoiceLinear
  }
  private struct Stage {
    let upsample: VibeVoiceConvolution
    let blocks: [Block]
  }
  private static let kernelSize = 7
  private static let expansion = 4
  static let samplesPerFrame = 3_200
  private let epsilon: Float
  private let latentDimensions: Int
  private let stages: [Stage]
  private let output: VibeVoiceConvolution

  init(configuration: VibeVoiceConfiguration.Codec, weights: VibeVoiceWeights) throws {
    epsilon = configuration.normalizationEpsilon
    latentDimensions = configuration.latentDimensions
    let root = "acoustic_tokenizer.decoder"
    func convolution(_ path: String, shape: [Int], operation: VibeVoiceConvolution.Operation) throws
      -> VibeVoiceConvolution
    {
      try VibeVoiceConvolution(
        weight: weights.tensor(path + ".weight", shape: shape),
        bias: weights.tensor(path + ".bias", shape: [shape[0]]), operation: operation)
    }
    stages = try configuration.depths.enumerated().map { index, depth in
      let channels = configuration.filters * (1 << (configuration.depths.count - 1 - index))
      let upsample: VibeVoiceConvolution
      if index == 0 {
        upsample = try convolution(
          root + ".upsample_layers.0.0.conv.conv",
          shape: [channels, Self.kernelSize, configuration.latentDimensions],
          operation: .causal(groups: 1))
      } else {
        let stride = configuration.ratios[index - 1]
        upsample = try convolution(
          root + ".upsample_layers.\(index).0.convtr.convtr",
          shape: [channels, stride * 2, channels * 2], operation: .upsample(stride: stride))
      }
      let blocks = try (0..<depth).map { blockIndex in
        let prefix = root + ".stages.\(index).\(blockIndex)"
        return try Block(
          norm: weights.tensor(prefix + ".norm.weight", shape: [channels]),
          feedForwardNorm: weights.tensor(prefix + ".ffn_norm.weight", shape: [channels]),
          mixer: convolution(
            prefix + ".mixer.conv.conv.conv", shape: [channels, Self.kernelSize, 1],
            operation: .causal(groups: channels)),
          mixerScale: weights.tensor(prefix + ".gamma", shape: [channels]),
          feedForwardScale: weights.tensor(prefix + ".ffn_gamma", shape: [channels]),
          input: weights.linear(
            prefix + ".ffn.linear1", input: channels, output: channels * Self.expansion),
          output: weights.linear(
            prefix + ".ffn.linear2", input: channels * Self.expansion, output: channels))
      }
      return Stage(upsample: upsample, blocks: blocks)
    }
    output = try convolution(
      root + ".head.conv.conv", shape: [1, Self.kernelSize, configuration.filters],
      operation: .causal(groups: 1))
  }

  func reset() {
    output.reset()
    for stage in stages {
      stage.upsample.reset()
      for block in stage.blocks { block.mixer.reset() }
    }
  }

  func decode(_ latent: MLXArray) throws -> [Float] {
    guard latent.shape == [1, latentDimensions] else {
      throw VibeVoiceError.invalidTensor("acoustic latent")
    }
    var hidden = latent.expandedDimensions(axis: 0)
    for stage in stages {
      try Task.checkCancellation()
      hidden = try stage.upsample(hidden)
      for block in stage.blocks {
        let normalized = MLXFast.rmsNorm(hidden, weight: block.norm, eps: epsilon)
        hidden = try hidden + block.mixer(normalized) * block.mixerScale
        let feedForward = MLXFast.rmsNorm(hidden, weight: block.feedForwardNorm, eps: epsilon)
        let projected = block.input(feedForward)
        let activated = 0.5 * projected * (1 + erf(projected * Float(1 / sqrt(2.0))))
        hidden = hidden + block.output(activated) * block.feedForwardScale
      }
      eval(hidden)
      stage.upsample.materialize()
      for block in stage.blocks { block.mixer.materialize() }
    }
    let samples = try output(hidden).asArray(Float.self)
    output.materialize()
    guard samples.count == Self.samplesPerFrame else {
      throw VibeVoiceError.invalidTensor("decoded frame")
    }
    return samples
  }
}
