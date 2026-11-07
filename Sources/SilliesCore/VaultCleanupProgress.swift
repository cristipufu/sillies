/// Cleanup acknowledges a durable request before reclaiming its files in bounded slices.
public struct VaultCleanupProgress: Sendable {
  public let isPending: Bool
  public let removedRecords: Int
  public init(isPending: Bool, removedRecords: Int) {
    self.isPending = isPending
    self.removedRecords = removedRecords
  }
}
