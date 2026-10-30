import CoreGraphics

/// Hand paths compensate for the body's eased climb, keeping contact until the release.
public enum PlayfulClamberGrip {
  private static let referenceSize = 100.0
  private static let releaseStart = 0.68
  private static let lowerHandOffset = 24.0
  private static let restingHands = [CGPoint(x: 42, y: 44), CGPoint(x: 86, y: 44)]

  public static func points(actor: PlayfulScenePlan.Actor, progress: Double) -> [CGPoint] {
    let scale = actor.participant.surface.presentationSize / referenceSize
    let from = actor.point(for: .outside, pose: .hangingRight)
    let to = actor.point(for: .outside)
    let eased = progress * progress * (3 - 2 * progress)
    let body = CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased)
    let offset = AttachmentPose.hangingRight.contactOffset(
      from: .standing, size: actor.participant.surface.presentationSize)
    let upper = CGPoint(x: from.x + offset.x, y: from.y + offset.y)
    let release = max(0, (progress - releaseStart) / (1 - releaseStart))
    return [upper.y - lowerHandOffset * scale, upper.y].enumerated().map { index, y in
      let held = CGPoint(
        x: AttachmentPose.standing.anchor.x + (body.x - upper.x) / scale,
        y: AttachmentPose.standing.anchor.y + (y - body.y) / scale)
      let rest = restingHands[index]
      return CGPoint(
        x: held.x + (rest.x - held.x) * release, y: held.y + (rest.y - held.y) * release)
    }
  }
}
