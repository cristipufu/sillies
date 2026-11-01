import Foundation

/// Shared spacing for drag menus and companion action menus, in screen coordinates.
public struct RadialMenuArc: Sendable {
  public static let defaultSweep: Double = 152
  private static let minimumRadius: Double = 118
  private static let targetSpacing: Double = 80
  public let radius: Double
  private let count: Int
  private let sweep: Double

  public init(count: Int, sweepDegrees: Double = Self.defaultSweep) {
    self.count = max(0, count)
    sweep = sweepDegrees * .pi / 180
    let gap = sweep / Double(max(1, self.count - 1))
    radius =
      count > 1
      ? max(Self.minimumRadius, Self.targetSpacing / (2 * sin(gap / 2))) : Self.minimumRadius
  }

  public func centers(around anchor: CGPoint, facingDegrees: Double) -> [CGPoint] {
    (0..<count).map { index in
      let fraction = count > 1 ? Double(index) / Double(count - 1) : 0.5
      let angle = facingDegrees * .pi / 180 + sweep * (0.5 - fraction)
      return CGPoint(x: anchor.x + radius * cos(angle), y: anchor.y + radius * sin(angle))
    }
  }
}
