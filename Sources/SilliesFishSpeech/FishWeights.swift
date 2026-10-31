import Foundation
import MLX

/// Confined to the inference actor. No network access, global cache, or implicit weight conversion.
final class FishWeights {
  private let tensors: [String: MLXArray]
  private let quantization: FishConfiguration.Quantization?

  init(tensors: [String: MLXArray], quantization: FishConfiguration.Quantization? = nil) {
    self.tensors = tensors
    self.quantization = quantization
  }

  func tensor(_ name: String, rank: Int) throws -> MLXArray {
    guard let value = tensors[name], value.ndim == rank, value.shape.allSatisfy({ $0 > 0 }) else {
      throw FishError.invalidTensor(name)
    }
    return value
  }

  func vector(_ name: String, count: Int) throws -> MLXArray {
    let value = try tensor(name, rank: 1)
    guard value.size == count else { throw FishError.invalidTensor(name) }
    return value
  }

  func linear(_ input: MLXArray, at path: String) throws -> MLXArray {
    let weight = try tensor(path + ".weight", rank: 2)
    let result: MLXArray
    if let quantization, let scales = tensors[path + ".scales"] {
      let biases = try tensor(path + ".biases", rank: 2)
      guard weight.dtype == .uint32, scales.shape == biases.shape,
        weight.dim(0) == scales.dim(0),
        weight.dim(1) * (32 / quantization.bits) == input.dim(-1),
        scales.dim(1) * quantization.groupSize == input.dim(-1)
      else { throw FishError.invalidTensor(path) }
      result = quantizedMM(
        input, weight, scales: scales, biases: biases,
        transpose: true, groupSize: quantization.groupSize, bits: quantization.bits)
    } else {
      guard weight.dim(1) == input.dim(-1) else { throw FishError.invalidTensor(path) }
      result = matmul(input, weight.T)
    }
    if tensors[path + ".bias"] != nil {
      return try result + vector(path + ".bias", count: result.dim(-1))
    }
    return result
  }

  func embedding(_ tokens: MLXArray, at path: String) throws -> MLXArray {
    let weight = try tensor(path + ".weight", rank: 2)
    if let quantization, let scales = tensors[path + ".scales"] {
      let biases = try tensor(path + ".biases", rank: 2)
      guard weight.dtype == .uint32, scales.shape == biases.shape,
        weight.dim(0) == scales.dim(0),
        weight.dim(1) * (32 / quantization.bits) == scales.dim(1) * quantization.groupSize
      else { throw FishError.invalidTensor(path) }
      return dequantized(
        weight[tokens], scales: scales[tokens], biases: biases[tokens],
        groupSize: quantization.groupSize, bits: quantization.bits)
    }
    return weight[tokens]
  }

  func normalized(_ input: MLXArray, at path: String, epsilon: Float) throws -> MLXArray {
    try MLXFast.rmsNorm(input, weight: vector(path + ".weight", count: input.dim(-1)), eps: epsilon)
  }

  func gatedFeedForward(_ input: MLXArray, at path: String) throws -> MLXArray {
    let gate = try linear(input, at: path + ".w1")
    let value = try linear(input, at: path + ".w3")
    return try linear((gate * sigmoid(gate)) * value, at: path + ".w2")
  }

  func selectingOutputRows(_ rows: [Int32], at path: String) throws -> FishWeights {
    let indices = MLXArray(rows)
    let weight = try tensor(path + ".weight", rank: 2)
    guard rows.allSatisfy({ $0 >= 0 && $0 < weight.dim(0) }) else {
      throw FishError.invalidTensor(path)
    }
    var selected = ["output.weight": weight[indices]]
    if quantization != nil {
      selected["output.scales"] = try tensor(path + ".scales", rank: 2)[indices]
      selected["output.biases"] = try tensor(path + ".biases", rank: 2)[indices]
    }
    for value in selected.values { eval(value) }
    return FishWeights(tensors: selected, quantization: quantization)
  }
}
