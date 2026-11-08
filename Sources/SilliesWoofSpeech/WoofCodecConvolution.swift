import MLX

/// Owns causal samples across decoder chunks; resetting an utterance clears all retained audio.
final class WoofCodecConvolution {
  enum Operation {
    case causal
    case upsample(stride: Int)
  }
  let inputChannels: Int
  let outputChannels: Int
  private let operation: Operation
  private let kernels: [MLXArray]
  private let bias: MLXArray
  private let historyLength: Int
  private var history: MLXArray?

  init(weight: MLXArray, bias: MLXArray, operation: Operation) throws {
    guard weight.ndim == 3, weight.shape.allSatisfy({ $0 > 0 }), weight.dim(2) <= 64 else {
      throw WoofModelError.invalidConfiguration
    }
    self.operation = operation
    self.bias = bias
    switch operation {
    case .causal:
      inputChannels = weight.dim(1)
      outputChannels = weight.dim(0)
      kernels = (0..<weight.dim(2)).map { weight[0..., 0..., $0].T }
      historyLength = weight.dim(2) - 1
    case .upsample(let stride):
      guard (1...16).contains(stride), weight.dim(2) == 2 * stride else {
        throw WoofModelError.invalidConfiguration
      }
      inputChannels = weight.dim(0)
      outputChannels = weight.dim(1)
      kernels = [weight.transposed(0, 2, 1).reshaped(inputChannels, -1)]
      historyLength = 1
    }
    guard bias.shape == [outputChannels] else { throw WoofModelError.invalidConfiguration }
    eval(kernels)
    eval(bias)
  }

  func reset() { history = nil }

  func callAsFunction(_ input: MLXArray) throws -> MLXArray {
    guard input.ndim == 2, input.dim(0) > 0, input.dim(1) == inputChannels else {
      throw WoofModelError.invalidConfiguration
    }
    switch operation {
    case .causal: return causal(input)
    case .upsample(let stride): return upsample(input, stride: stride)
    }
  }

  func materialize() { if let history { eval(history) } }

  private func causal(_ input: MLXArray) -> MLXArray {
    let previous = history ?? MLXArray.zeros([historyLength, inputChannels])
    let padded = concatenated([previous, input], axis: 0)
    if historyLength > 0 { history = padded[(padded.dim(0) - historyLength)...] }
    // Small causal kernels become matrix products. MLX's CPU convolution otherwise uses
    // its scalar slow_conv_1D fallback, which dominates this compact decoder's runtime.
    var output = matmul(padded[..<input.dim(0)], kernels[0]) + bias
    for tap in 1..<kernels.count {
      output = output + matmul(padded[tap..<(tap + input.dim(0))], kernels[tap])
    }
    return output
  }

  private func upsample(_ input: MLXArray, stride: Int) -> MLXArray {
    let width = stride * outputChannels
    let projected = matmul(input, kernels[0])
    let previous = history ?? MLXArray.zeros([1, width])
    let tail = projected[0..., width...]
    let carried = concatenated([previous, tail[..<(input.dim(0) - 1)]], axis: 0)
    history = tail[(input.dim(0) - 1)...]
    return (projected[0..., ..<width] + carried).reshaped(input.dim(0) * stride, outputChannels)
      + bias
  }
}
