import Foundation
import MLX

/// Codec tensors use PyTorch's channel-first layout; layout conversion stays at this boundary.
final class FishCodecConvolution {
  struct Geometry {
    var stride = 1
    var dilation = 1
    var groups = 1
  }
  private static let normalizationEpsilon: Float = 1e-12
  private static let snakeEpsilon: Float = 1e-9
  private let weights: FishWeights
  private var kernels: [String: MLXArray] = [:]
  private var history: [String: MLXArray] = [:]
  func reset() { history.removeAll() }

  init(weights: FishWeights) { self.weights = weights }

  func forward(_ input: MLXArray, at path: String, geometry: Geometry = .init()) throws -> MLXArray
  {
    let weight = try kernel(at: path)
    guard input.ndim == 3, input.dim(1) == weight.dim(1) * geometry.groups else {
      throw FishError.invalidTensor(path)
    }
    let padding = (weight.dim(2) - 1) * geometry.dilation + 1 - geometry.stride
    guard geometry.stride == 1 else { throw FishError.invalidTensor(path) }
    let previous =
      history[path] ?? MLXArray.zeros([input.dim(0), input.dim(1), padding], dtype: input.dtype)
    let padded = concatenated([previous, input], axis: 2)
    if padding > 0 {
      let retained = padded[0..., 0..., (padded.dim(2) - padding)...]
      eval(retained)
      history[path] = retained
    }
    let output = conv1d(
      padded.transposed(0, 2, 1), weight.transposed(0, 2, 1),
      stride: geometry.stride, dilation: geometry.dilation, groups: geometry.groups)
    return try (output + weights.vector(path + ".bias", count: output.dim(2))).transposed(0, 2, 1)
  }

  func upsample(_ input: MLXArray, at path: String, stride: Int) throws -> MLXArray {
    let weight = try kernel(at: path)
    guard input.ndim == 3, input.dim(1) == weight.dim(0), weight.dim(2) >= stride else {
      throw FishError.invalidTensor(path)
    }
    let prior = history[path]
    let combined = prior.map { concatenated([$0, input], axis: 2) } ?? input
    let offset = (prior?.dim(2) ?? 0) * stride
    let output = convTransposed1d(
      combined.transposed(0, 2, 1), weight.transposed(1, 2, 0), stride: stride,
      outputPadding: stride > 1 ? 1 : 0)
    let biased = try output + weights.vector(path + ".bias", count: output.dim(2))
    let length = input.dim(2) * stride
    let retainedFrames = min(combined.dim(2), (weight.dim(2) - 1) / stride)
    if retainedFrames > 0 {
      let retained = combined[0..., 0..., (combined.dim(2) - retainedFrames)...]
      eval(retained)
      history[path] = retained
    }
    return biased[0..., offset..<(offset + length), 0...].transposed(0, 2, 1)
  }

  func snake(_ input: MLXArray, at path: String) throws -> MLXArray {
    let alpha = try weights.tensor(path + ".alpha", rank: 3)
    guard alpha.shape == [1, input.dim(1), 1] else { throw FishError.invalidTensor(path) }
    return input + square(sin(alpha * input)) / (alpha + Self.snakeEpsilon)
  }

  private func kernel(at path: String) throws -> MLXArray {
    if let cached = kernels[path] { return cached }
    let kernel: MLXArray
    if path.hasSuffix(".conv") {
      kernel = try weights.tensor(path + ".weight", rank: 3)
    } else {
      let direction = try weights.tensor(path + ".weight_v", rank: 3)
      let magnitude = try weights.tensor(path + ".weight_g", rank: 3)
      guard magnitude.shape == [direction.dim(0), 1, 1] else { throw FishError.invalidTensor(path) }
      kernel =
        magnitude * direction
        / (sqrt(sum(square(direction), axes: [1, 2], keepDims: true)) + Self.normalizationEpsilon)
    }
    eval(kernel)
    kernels[path] = kernel
    return kernel
  }
}
