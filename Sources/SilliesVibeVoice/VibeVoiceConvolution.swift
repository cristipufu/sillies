import MLX

/// Each codec layer retains only the samples required by its causal kernel.
final class VibeVoiceConvolution {
  enum Operation {
    case causal(groups: Int)
    case upsample(stride: Int)
  }
  private let weight: MLXArray
  private let bias: MLXArray
  private let inputChannels: Int
  private let operation: Operation
  private var history: MLXArray?

  init(weight: MLXArray, bias: MLXArray, operation: Operation) throws {
    guard weight.ndim == 3, weight.shape.allSatisfy({ $0 > 0 }),
      weight.dim(1) <= 32, bias.shape == [weight.dim(0)]
    else {
      throw VibeVoiceError.invalidTensor("convolution")
    }
    switch operation {
    case .causal(let groups):
      guard groups > 0, groups <= weight.dim(0), weight.dim(0).isMultiple(of: groups) else {
        throw VibeVoiceError.invalidTensor("convolution groups")
      }
      inputChannels = weight.dim(2) * groups
    case .upsample(let stride):
      guard (1...16).contains(stride), weight.dim(1) == 2 * stride else {
        throw VibeVoiceError.invalidTensor("convolution stride")
      }
      inputChannels = weight.dim(2)
    }
    self.weight = weight
    self.bias = bias
    self.operation = operation
    eval(weight, bias)
  }

  func reset() { history = nil }
  func materialize() { if let history { eval(history) } }

  func callAsFunction(_ input: MLXArray) throws -> MLXArray {
    guard input.ndim == 3, input.dim(0) == 1, input.dim(1) > 0, input.dim(2) == inputChannels else {
      throw VibeVoiceError.invalidTensor("convolution input")
    }
    switch operation {
    case .causal(let groups):
      let context = weight.dim(1) - 1
      let previous = history ?? MLXArray.zeros([1, context, inputChannels])
      let combined = concatenated([previous, input], axis: 1)
      if context > 0 { history = combined[0..., (combined.dim(1) - context)..., 0...] }
      return conv1d(combined, weight, groups: groups) + bias
    case .upsample(let stride):
      let previousFrames = history?.dim(1) ?? 0
      let combined = history.map { concatenated([$0, input], axis: 1) } ?? input
      let result = convTransposed1d(combined, weight, stride: stride) + bias
      history = combined[0..., (combined.dim(1) - 1)..., 0...]
      let first = previousFrames * stride
      return result[0..., first..<(first + input.dim(1) * stride), 0...]
    }
  }
}
