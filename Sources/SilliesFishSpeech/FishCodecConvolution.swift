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

  init(weights: FishWeights) { self.weights = weights }

  func forward(_ input: MLXArray, at path: String, geometry: Geometry = .init()) throws -> MLXArray
  {
    let weight = try kernel(at: path)
    guard input.ndim == 3, input.dim(1) == weight.dim(1) * geometry.groups else {
      throw FishError.invalidTensor(path)
    }
    let padding = (weight.dim(2) - 1) * geometry.dilation + 1 - geometry.stride
    let padded = MLX.padded(input, widths: [.init(0), .init(0), .init((padding, 0))])
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
    let output = convTransposed1d(
      input.transposed(0, 2, 1), weight.transposed(1, 2, 0), stride: stride,
      outputPadding: stride > 1 ? 1 : 0)
    let biased = try output + weights.vector(path + ".bias", count: output.dim(2))
    let length = biased.dim(1) - (weight.dim(2) - stride)
    return biased[0..., 0..<length, 0...].transposed(0, 2, 1)
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
