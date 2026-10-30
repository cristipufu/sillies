import Foundation

/// Shared distance and timing policy for settling a displaced companion into a free slot.
public struct PerchSettlement: Sendable {
  private static let positionTolerance: Double = 0.5
  private static let minimumDuration: Double = 0.12
  private static let maximumDuration: Double = 0.24
  private static let speedPointsPerSecond: Double = 360
  public let requiresMovement: Bool
  public let duration: Double

  public init(from origin: CGPoint, to target: CGPoint) {
    let distance = hypot(target.x - origin.x, target.y - origin.y)
    requiresMovement = distance > Self.positionTolerance
    duration = min(
      Self.maximumDuration, max(Self.minimumDuration, distance / Self.speedPointsPerSecond))
  }
}
