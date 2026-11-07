import Foundation

public struct VaultVectorIndexSnapshot: Sendable {
  public let space: String
  public let epoch: String
  public let dimensions: Int
  public let count: Int
  public let maximumID: Int64
  public let latestChange: Int64
  public let earliestChange: Int64
  public func bounded(through id: Int64) -> Self {
    .init(
      space: space, epoch: epoch, dimensions: dimensions, count: count,
      maximumID: min(maximumID, id), latestChange: latestChange, earliestChange: earliestChange)
  }
}

public struct VaultVectorBatch: Sendable {
  public let ids: [Int64]
  public let values: [Float]
}

public struct VaultVectorChanges: Sendable {
  public let removed: [Int64]
  public let inserted: VaultVectorBatch
  public let through: Int64
}
