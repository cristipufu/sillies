import CoreGraphics

/// Body travel and hand placement share one reversible corner path, independent of renderer clocks.
public struct PlayfulClamberMotion: Sendable {
  public enum Direction: Sendable { case pullUp, lowerDown }
  private enum Timing {
    static let transferStart = 0.58
    static let ledgeGripEnd = 0.76
    static let releaseStart = 0.88
  }
  private enum Geometry {
    static let referenceSize = 100.0
    static let liftClearanceRatio = 0.10
    static let handClearanceRatio = 0.07
  }
  private enum Hand: CaseIterable {
    case lower, upper

    var reach: ClosedRange<Double> { self == .lower ? 0.24...0.46 : 0.10...0.28 }
    var ledgeInsetRatio: Double { self == .lower ? 0.28 : 0.10 }
    var initialDrop: Double { self == .lower ? 24 : 0 }
    var restingPoint: CGPoint {
      self == .lower ? CGPoint(x: 42, y: 44) : CGPoint(x: 86, y: 44)
    }
  }
  private let actor: PlayfulScenePlan.Actor
  private let direction: Direction
  private var size: Double { actor.participant.surface.presentationSize }
  private var scale: Double { size / Geometry.referenceSize }
  private var start: CGPoint { actor.point(for: .outside, pose: .hangingRight) }

  public init(actor: PlayfulScenePlan.Actor, direction: Direction = .pullUp) {
    self.actor = actor
    self.direction = direction
  }

  public func position(at progress: Double) -> CGPoint {
    pullUpPosition(at: pullUpProgress(progress))
  }

  private func pullUpPosition(at progress: Double) -> CGPoint {
    let raised = CGPoint(x: start.x, y: actor.corner.y + size * Geometry.liftClearanceRatio)
    if progress < Timing.transferStart {
      return interpolate(start, raised, progress: progress / Timing.transferStart)
    }
    return interpolate(
      raised, actor.corner, progress: (progress - Timing.transferStart) / (1 - Timing.transferStart)
    )
  }

  public func edge(at progress: Double) -> PerchSurface.Edge {
    pullUpProgress(progress) < Timing.transferStart ? .right : .top
  }

  public func handPoints(at progress: Double) -> [CGPoint] {
    let progress = pullUpProgress(progress)
    let body = pullUpPosition(at: progress)
    let offset = AttachmentPose.hangingRight.contactOffset(from: .standing, size: size)
    let release = (progress - Timing.releaseStart) / (1 - Timing.releaseStart)
    return Hand.allCases.map { hand in
      let initial = CGPoint(
        x: actor.exteriorEdgeX, y: start.y + offset.y - hand.initialDrop * scale)
      let corner = CGPoint(
        x: actor.exteriorEdgeX, y: actor.corner.y + size * Geometry.handClearanceRatio)
      let ledge = CGPoint(
        x: actor.exteriorEdgeX - size * hand.ledgeInsetRatio,
        y: corner.y)
      let reach =
        (progress - hand.reach.lowerBound) / (hand.reach.upperBound - hand.reach.lowerBound)
      let sideGrip = interpolate(initial, corner, progress: reach)
      let transfer =
        (progress - Timing.transferStart) / (Timing.ledgeGripEnd - Timing.transferStart)
      let world = interpolate(sideGrip, ledge, progress: transfer)
      let held = CGPoint(
        x: AttachmentPose.standing.anchor.x + (body.x - world.x) / scale,
        y: AttachmentPose.standing.anchor.y + (world.y - body.y) / scale)
      return interpolate(held, hand.restingPoint, progress: release)
    }
  }

  private func pullUpProgress(_ progress: Double) -> Double {
    direction == .pullUp ? progress : 1 - progress
  }

  private func interpolate(_ from: CGPoint, _ to: CGPoint, progress: Double) -> CGPoint {
    let fraction = min(max(progress, 0), 1)
    let eased = fraction * fraction * (3 - 2 * fraction)
    return CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased)
  }
}
