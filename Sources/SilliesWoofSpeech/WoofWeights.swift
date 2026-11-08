import Foundation
import MLX

/// Validates every file-backed dimension before entering MLX's precondition-based APIs.
struct WoofWeights {
  let arrays: [String: WoofNumpyArray]

  func tensor(_ reference: WoofTensorReference) throws -> MLXArray {
    guard let array = arrays[reference.name] else {
      throw WoofModelError.missingTensor(reference.name)
    }
    guard !array.storage.isEmpty,
      array.shape.allSatisfy({ $0 > 0 && $0 <= Int(Int32.max) })
    else { throw WoofModelError.invalidTensor(reference.name) }
    let type: DType
    switch array.scalarType {
    case .int8: type = .int8
    case .uint8: type = .uint8
    case .int32: type = .int32
    case .int64: type = .int64
    case .float16: type = .float16
    case .float32: type = .float32
    case .unicode: throw WoofModelError.invalidTensor(reference.name)
    }
    return MLXArray(array.storage, array.shape, dtype: type).asType(.float32)
  }

  func tensor(_ reference: WoofTensorReference, shape: [Int]) throws -> MLXArray {
    let result = try tensor(reference)
    guard result.shape == shape else { throw WoofModelError.invalidTensor(reference.name) }
    return result
  }

  func tensor(_ parameter: WoofTensorParameter) throws -> MLXArray {
    switch parameter {
    case .array(let reference): return try tensor(reference)
    case .grouped(let group): return try dequantize(group)
    }
  }

  func linear(_ parameter: WoofLinearParameter) throws -> WoofLinear {
    let weight: MLXArray
    if let quantized = parameter.quantized, let scale = parameter.scale, parameter.weight == nil {
      let values = try tensor(quantized)
      guard values.ndim == 2 else { throw WoofModelError.invalidTensor(quantized.name) }
      weight = try values * tensor(scale, shape: [values.dim(0)]).expandedDimensions(axis: 1)
    } else if let plain = parameter.weight, parameter.quantized == nil, parameter.scale == nil {
      weight = try tensor(plain)
    } else {
      throw WoofModelError.invalidConfiguration
    }
    return try WoofLinear(weight: weight, bias: parameter.bias.map { try tensor($0) })
  }

  private func dequantize(_ group: WoofTensorParameter.Grouped) throws -> MLXArray {
    let values = try tensor(group.quantized)
    let scales = try tensor(group.scale)
    guard values.ndim == 2, scales.ndim == 2,
      (1...8).contains(group.shape.count), group.shape.indices.contains(group.axis),
      group.shape.allSatisfy({ (1...65_536).contains($0) }), (1...1_024).contains(group.groupSize),
      scales.dim(0) == values.dim(0), group.shape[group.axis] == values.dim(0)
    else { throw WoofModelError.invalidTensor(group.quantized.name) }
    let columns = scales.dim(1) * group.groupSize
    guard columns >= values.dim(1), columns - values.dim(1) < group.groupSize else {
      throw WoofModelError.invalidTensor(group.quantized.name)
    }
    var remainingShape = group.shape
    remainingShape.remove(at: group.axis)
    var expectedColumns = 1
    for dimension in remainingShape {
      let product = expectedColumns.multipliedReportingOverflow(by: dimension)
      guard !product.overflow else { throw WoofModelError.invalidTensor(group.quantized.name) }
      expectedColumns = product.partialValue
    }
    guard expectedColumns == values.dim(1) else {
      throw WoofModelError.invalidTensor(group.quantized.name)
    }
    let padding = MLXArray.zeros([values.dim(0), columns - values.dim(1)])
    let padded = concatenated([values, padding], axis: 1)
    let expanded =
      padded.reshaped(values.dim(0), scales.dim(1), group.groupSize)
      * scales.expandedDimensions(axis: 2)
    let matrix = expanded.reshaped(values.dim(0), columns)[0..., ..<values.dim(1)]
    let leading = matrix.reshaped([values.dim(0)] + remainingShape)
    var axes = Array(group.shape.indices)
    axes.removeFirst()
    axes.insert(0, at: group.axis)
    return leading.transposed(axes: axes)
  }
}
