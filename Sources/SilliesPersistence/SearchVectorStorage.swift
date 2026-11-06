import Foundation
import SilliesCore

enum SearchVectorStorage {
  static let maximumBytes = SearchEmbedding.maximumDimensions * MemoryLayout<UInt32>.size
  static func encode(_ values: [Float]) -> Data {
    values.map { $0.bitPattern.littleEndian }.withUnsafeBytes { Data($0) }
  }
}
