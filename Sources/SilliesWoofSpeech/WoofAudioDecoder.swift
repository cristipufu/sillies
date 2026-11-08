import MLX

final class WoofAudioDecoder {
  private enum Stage {
    case convolution(WoofCodecConvolution)
    case residual(WoofCodecConvolution, WoofCodecConvolution)
    case activation
  }
  private let transformer: WoofDecoderTransformer
  private let stages: [Stage]
  private let convolutions: [WoofCodecConvolution]

  init(configuration: WoofConfiguration.Decoder, weights: WoofWeights, latentDimensions: Int)
    throws
  {
    transformer = try WoofDecoderTransformer(
      configuration: configuration, weights: weights, latentDimensions: latentDimensions)
    var stages: [Stage] = []
    var convolutions: [WoofCodecConvolution] = []
    var channels = configuration.attention.heads * configuration.attention.headDimensions
    var samplesPerFrame = 1
    func convolution(
      _ parameter: WoofDecoderOperation.Convolution, operation: WoofCodecConvolution.Operation
    )
      throws -> WoofCodecConvolution
    {
      try WoofCodecConvolution(
        weight: weights.tensor(parameter.weight), bias: weights.tensor(parameter.bias),
        operation: operation
      )
    }
    for operation in configuration.convolutions {
      switch operation {
      case .activation: stages.append(.activation)
      case .residual(let first, let second):
        let input = try convolution(first, operation: .causal)
        let output = try convolution(second, operation: .causal)
        guard input.inputChannels == channels, output.outputChannels == channels,
          input.outputChannels == output.inputChannels
        else { throw WoofModelError.invalidConfiguration }
        stages.append(.residual(input, output))
        convolutions += [input, output]
      case .convolution(let parameters), .upsample(let parameters):
        let mode: WoofCodecConvolution.Operation
        if case .upsample = operation {
          guard let stride = parameters.stride, (1...16).contains(stride),
            samplesPerFrame <= WoofConfiguration.samplesPerFrame / stride
          else {
            throw WoofModelError.invalidConfiguration
          }
          samplesPerFrame *= stride
          mode = .upsample(stride: stride)
        } else {
          mode = .causal
        }
        let layer = try convolution(parameters, operation: mode)
        guard layer.inputChannels == channels else { throw WoofModelError.invalidConfiguration }
        channels = layer.outputChannels
        stages.append(.convolution(layer))
        convolutions.append(layer)
      }
    }
    guard channels == 1, samplesPerFrame == WoofConfiguration.samplesPerFrame else {
      throw WoofModelError.invalidConfiguration
    }
    self.stages = stages
    self.convolutions = convolutions
  }

  func reset() {
    transformer.reset()
    for convolution in convolutions { convolution.reset() }
  }

  func decode(_ latents: MLXArray) throws -> [Float] {
    var hidden = try transformer(latents)
    for stage in stages {
      try Task.checkCancellation()
      switch stage {
      case .activation: hidden = activate(hidden)
      case .convolution(let layer): hidden = try layer(hidden)
      case .residual(let first, let second):
        hidden = try hidden + second(activate(first(activate(hidden))))
      }
    }
    let samples = hidden.asArray(Float.self)
    for convolution in convolutions { convolution.materialize() }
    return samples
  }

  private func activate(_ input: MLXArray) -> MLXArray {
    maximum(input, 0) + expm1(minimum(input, 0))
  }
}
