import Foundation

/// Keeps the mascot at the center; the actions turn inward at display edges and corners.
public struct CompanionActionMenuLayout: Sendable {
  private static let screenInset: CGFloat = 4
  private static let cornerSweep: Double = 72
  public let anchor: CGPoint
  public let centers: [CGPoint]
  public let radius: Double
  public let frame: CGRect

  public init(anchor: CGPoint, count: Int, itemSize: CGSize, visibleFrame: CGRect) {
    let available = visibleFrame.insetBy(dx: Self.screenInset, dy: Self.screenInset)
    let arc = RadialMenuArc(count: count)
    let cornerArc = RadialMenuArc(count: count, sweepDegrees: Self.cornerSweep)
    let candidates =
      [90.0, -90, 0, 180].map { (arc, $0) }
      + [45.0, 135, 225, 315].map { (cornerArc, $0) }
    let options = candidates.map { arc, direction in
      let centers = arc.centers(around: anchor, facingDegrees: direction)
      let bounds = centers.map { center in
        CGRect(
          x: center.x - itemSize.width / 2, y: center.y - itemSize.height / 2,
          width: itemSize.width, height: itemSize.height)
      }
      let overflow = bounds.reduce(CGFloat.zero) { total, rect in
        total + max(0, available.minX - rect.minX) + max(0, rect.maxX - available.maxX)
          + max(0, available.minY - rect.minY) + max(0, rect.maxY - available.maxY)
      }
      return (arc: arc, centers: centers, overflow: overflow)
    }
    let best = options.min { $0.overflow < $1.overflow }
    self.anchor = anchor
    centers = best?.centers ?? []
    radius = best?.arc.radius ?? arc.radius
    let extent = radius + max(itemSize.width, itemSize.height) / 2
    frame = CGRect(
      x: anchor.x - extent, y: anchor.y - extent, width: extent * 2, height: extent * 2)
  }
}
