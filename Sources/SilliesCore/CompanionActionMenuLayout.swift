import Foundation

/// Keeps the mascot at the center; the actions turn inward at display edges and corners.
public struct CompanionActionMenuLayout: Sendable {
  private static let screenInset: CGFloat = 4
  private static let minimumSweep: Double = 72
  private static let sweepStep: Double = 8
  private static let directions = [90.0, -90, 0, 180, 45, 135, 225, 315]
  public let anchor: CGPoint
  public let centers: [CGPoint]
  public let radius: Double
  public let frame: CGRect

  public init(anchor: CGPoint, count: Int, itemSize: CGSize, visibleFrame: CGRect) {
    let arc = RadialMenuArc(count: count)
    let placement = Placement(
      anchor: anchor, itemSize: itemSize,
      available: visibleFrame.insetBy(dx: Self.screenInset, dy: Self.screenInset))
    let sweeps = stride(
      from: RadialMenuArc.defaultSweep, through: Self.minimumSweep, by: -Self.sweepStep)
    let options = sweeps.flatMap { sweep in
      let candidateArc = RadialMenuArc(count: count, sweepDegrees: sweep)
      return Self.directions.map {
        Candidate(arc: candidateArc, direction: $0, placement: placement)
      }
    }
    let best = options.min { $0.isPreferred(to: $1) }
    self.anchor = anchor
    centers = best?.centers ?? []
    radius = best?.arc.radius ?? arc.radius
    let extent = radius + max(itemSize.width, itemSize.height) / 2
    frame = CGRect(
      x: anchor.x - extent, y: anchor.y - extent, width: extent * 2, height: extent * 2)
  }

  private struct Placement {
    let anchor: CGPoint
    let itemSize: CGSize
    let available: CGRect

    func overflow(at center: CGPoint) -> CGFloat {
      let rect = CGRect(
        x: center.x - itemSize.width / 2, y: center.y - itemSize.height / 2,
        width: itemSize.width, height: itemSize.height)
      return max(0, available.minX - rect.minX) + max(0, rect.maxX - available.maxX)
        + max(0, available.minY - rect.minY) + max(0, rect.maxY - available.maxY)
    }
  }

  private struct Candidate {
    let arc: RadialMenuArc
    let centers: [CGPoint]
    let overflow: CGFloat

    init(arc: RadialMenuArc, direction: Double, placement: Placement) {
      self.arc = arc
      centers = arc.centers(around: placement.anchor, facingDegrees: direction)
      overflow = centers.reduce(0) { $0 + placement.overflow(at: $1) }
    }

    func isPreferred(to other: Candidate) -> Bool {
      if overflow != other.overflow { return overflow < other.overflow }
      return arc.radius < other.arc.radius
    }
  }
}
