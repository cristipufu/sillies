import CoreML
import Foundation
@preconcurrency import WhisperKit

enum PromptAlignmentWeights {
  static func removingPrefix(_ rows: Int, from source: MLMultiArray) throws -> MLMultiArray {
    guard rows > 0 else { return source }
    guard source.shape.count == 2, rows < source.shape[0].intValue,
      source.strides[1].intValue == 1
    else {
      throw WhisperError.segmentingFailed(
        "Unexpected attention matrix layout: shape \(source.shape), strides \(source.strides).")
    }
    let shape: [NSNumber] = [NSNumber(value: source.shape[0].intValue - rows), source.shape[1]]
    let aligned = try MLMultiArray(shape: shape, dataType: source.dataType)
    let elementSize = try elementBytes(source.dataType)
    let rowBytes = source.shape[1].intValue * elementSize
    // Core ML may pad each row. Use the buffer's strides, not a packed-matrix assumption.
    source.withUnsafeMutableBytes { original, originalStrides in
      aligned.withUnsafeMutableBytes { destination, destinationStrides in
        for row in 0..<shape[0].intValue {
          let start = (row + rows) * originalStrides[0] * elementSize
          let target = row * destinationStrides[0] * elementSize
          UnsafeMutableRawBufferPointer(rebasing: destination[target..<(target + rowBytes)])
            .copyMemory(
              from: UnsafeRawBufferPointer(rebasing: original[start..<(start + rowBytes)]))
        }
      }
    }
    return aligned
  }

  private static func elementBytes(_ type: MLMultiArrayDataType) throws -> Int {
    switch type {
    case .float16: MemoryLayout<Float16>.stride
    case .float32: MemoryLayout<Float>.stride
    case .double: MemoryLayout<Double>.stride
    default: throw WhisperError.segmentingFailed("Unsupported attention matrix data type.")
    }
  }
}
