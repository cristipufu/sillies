import Foundation
import SilliesCore

/// Prepare the query once and score borrowed SQLite vectors without per-row allocations.
struct MemoryVectorQuery {
  private typealias Block = SIMD4<Double>
  private static let scalarBytes = MemoryLayout<UInt32>.size
  private let blocks: [Block]
  private let remainder: [Double]
  private let expectedBytes: Int

  init(_ embedding: MemoryEmbedding) {
    let values = embedding.values
    expectedBytes = values.count * Self.scalarBytes
    let blockEnd = values.count - values.count % Block.scalarCount
    blocks = stride(from: 0, to: blockEnd, by: Block.scalarCount).map { index in
      Block(
        Double(values[index]), Double(values[index + 1]),
        Double(values[index + 2]), Double(values[index + 3]))
    }
    remainder = values[blockEnd...].map(Double.init)
  }

  func similarity(_ bytes: UnsafeRawBufferPointer) throws -> Float {
    guard bytes.count == expectedBytes else { throw ConversationStorageError.invalidData }
    var dot = Block.zero
    var squaredLength = Block.zero
    for index in blocks.indices {
      let value = Self.block(bytes, at: index * Block.scalarCount * Self.scalarBytes)
      dot += value * blocks[index]
      squaredLength += value * value
    }
    var totalDot = dot.sum()
    var totalLength = squaredLength.sum()
    let remainderOffset = blocks.count * Block.scalarCount * Self.scalarBytes
    for index in remainder.indices {
      let value = Self.scalar(bytes, at: remainderOffset + index * Self.scalarBytes)
      totalDot += value * remainder[index]
      totalLength += value * value
    }
    // A nonfinite component also makes the squared norm nonfinite. No corrupt row is accepted.
    guard totalLength > 0, totalLength.isFinite, totalDot.isFinite else {
      throw ConversationStorageError.invalidData
    }
    return Float(totalDot / sqrt(totalLength))
  }

  private static func block(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> Block {
    let bits = bytes.loadUnaligned(fromByteOffset: offset, as: SIMD4<UInt32>.self)
    return Block(
      Double(Float(bitPattern: UInt32(littleEndian: bits.x))),
      Double(Float(bitPattern: UInt32(littleEndian: bits.y))),
      Double(Float(bitPattern: UInt32(littleEndian: bits.z))),
      Double(Float(bitPattern: UInt32(littleEndian: bits.w))))
  }

  private static func scalar(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> Double {
    Double(
      Float(
        bitPattern: UInt32(
          littleEndian:
            bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))))
  }
}
