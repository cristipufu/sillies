import Foundation

/// Captured and decoded only on a worker; dictionaries never cross an actor boundary.
public struct WindowMetadataSnapshot {
  public let entries: [[String: Any]]
  public let capturedAt: TimeInterval

  public init(entries: [[String: Any]], capturedAt: TimeInterval) {
    self.entries = entries
    self.capturedAt = capturedAt
  }
}
