import Foundation
import SilliesCore

enum MemoryVectorStorage {
  static let maximumBytes = MemoryEmbedding.maximumDimensions * MemoryLayout<UInt32>.size
  static func encode(_ values: [Float]) -> Data {
    values.map { $0.bitPattern.littleEndian }.withUnsafeBytes { Data($0) }
  }
}
