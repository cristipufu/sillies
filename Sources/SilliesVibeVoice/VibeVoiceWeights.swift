import MLX

/// File-backed tensors are checked once, while constructing the model's typed layers.
struct VibeVoiceWeights {
  let tensors: [String: MLXArray]
  let quantization: VibeVoiceConfiguration.Quantization

  func tensor(_ name: String, shape: [Int]) throws -> MLXArray {
    guard let value = tensors[name], value.shape == shape, value.dtype.isFloatingPoint else {
      throw VibeVoiceError.invalidTensor(name)
    }
    return value.asType(.float32)
  }

  func linear(_ name: String, input: Int, output: Int) throws -> VibeVoiceLinear {
    try VibeVoiceLinear(name: name, input: input, output: output, weights: self)
  }

  func embedding(_ name: String, rows: Int, dimensions: Int) throws -> VibeVoiceEmbedding {
    let projection = try linear(name, input: dimensions, output: rows)
    return VibeVoiceEmbedding(projection: projection)
  }
}

struct VibeVoiceLinear {
  private let weight: MLXArray
  private let scales: MLXArray?
  private let offsets: MLXArray?
  private let bias: MLXArray?
  private let quantization: VibeVoiceConfiguration.Quantization
  let inputDimensions: Int
  let outputDimensions: Int

  init(name: String, input: Int, output: Int, weights: VibeVoiceWeights) throws {
    guard weights.quantization.isSupported, input > 0, output > 0 else {
      throw VibeVoiceError.invalidTensor(name)
    }
    quantization = weights.quantization
    inputDimensions = input
    outputDimensions = output
    if let scales = weights.tensors[name + ".scales"] {
      guard let packed = weights.tensors[name + ".weight"], packed.dtype == .uint32,
        packed.shape == [output, input / (32 / quantization.bits)],
        input.isMultiple(of: quantization.groupSize),
        scales.shape == [output, input / quantization.groupSize], scales.dtype.isFloatingPoint
      else { throw VibeVoiceError.invalidTensor(name) }
      weight = packed
      self.scales = scales.asType(.float32)
      offsets = try weights.tensor(name + ".biases", shape: scales.shape)
    } else {
      weight = try weights.tensor(name + ".weight", shape: [output, input])
      scales = nil
      offsets = nil
    }
    bias =
      weights.tensors[name + ".bias"] == nil
      ? nil : try weights.tensor(name + ".bias", shape: [output])
  }

  func callAsFunction(_ input: MLXArray) -> MLXArray {
    let result: MLXArray
    if let scales, let offsets {
      result = quantizedMM(
        input, weight, scales: scales, biases: offsets,
        transpose: true, groupSize: quantization.groupSize, bits: quantization.bits)
    } else {
      result = matmul(input, weight.T)
    }
    return bias.map { result + $0 } ?? result
  }

  fileprivate func rows(_ indices: [Int32]) throws -> MLXArray {
    guard !indices.isEmpty, indices.allSatisfy({ $0 >= 0 && $0 < outputDimensions }) else {
      throw VibeVoiceError.invalidTensor("embedding indices")
    }
    let selected = MLXArray(indices)
    if let scales, let offsets {
      return dequantized(
        weight[selected], scales: scales[selected], biases: offsets[selected],
        groupSize: quantization.groupSize, bits: quantization.bits)
    }
    return weight[selected]
  }
}

struct VibeVoiceEmbedding {
  let projection: VibeVoiceLinear
  func callAsFunction(_ indices: [Int32]) throws -> MLXArray { try projection.rows(indices) }
}
