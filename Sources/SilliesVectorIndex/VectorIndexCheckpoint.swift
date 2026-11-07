import Foundation
import SilliesPersistence

/// A dirty marker makes an interrupted native write a rebuild, never a trusted partial checkpoint.
struct VectorIndexCheckpoint: Codable, Equatable {
  static let formatVersion = 1
  let version: Int
  let epoch: String
  let dimensions: Int
  let partitions: Int
  let trainedCount: Int
  let baseMaximumID: Int64
  var lastID: Int64 = 0
  var changeSequence: Int64
  var isComplete = false

  init(snapshot: VaultVectorIndexSnapshot, partitions: Int) {
    version = Self.formatVersion
    epoch = snapshot.epoch
    dimensions = snapshot.dimensions
    self.partitions = partitions
    trainedCount = snapshot.count
    baseMaximumID = snapshot.maximumID
    changeSequence = snapshot.latestChange
  }

  func accepts(_ snapshot: VaultVectorIndexSnapshot) -> Bool {
    version == Self.formatVersion && epoch == snapshot.epoch && dimensions == snapshot.dimensions
      && changeSequence >= snapshot.earliestChange - 1 && lastID >= 0
      && baseMaximumID >= lastID && trainedCount > 0 && partitions >= 0 && partitions <= 256
  }
}
