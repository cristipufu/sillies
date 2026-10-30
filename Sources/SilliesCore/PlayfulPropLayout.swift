import CoreGraphics

public enum PlayfulPropLayout {
  private static let signHeightRatio = 1.25
  private static let handHeightRatio = 0.32
  private static let handReachRatio = 0.19
  private static let ropeMargin: Double = 12
  private static let fireSize = CGSize(width: 53, height: 61)
  private static let parachuteWidthRatio = 1.4
  private static let parachuteHeightRatio = 1.75
  private static let referenceSize = 100.0
  private static let messageHeightAllowance = 120.0
  private static let ropeTailRatio = 0.36
  private static let ropeAnchorBackingHeight = 20.0
  public static let parachuteTemplateSize = CGSize(width: 90, height: 112)
  public static let parachuteLeftGrip = CGPoint(x: 26, y: 70)
  public static let parachuteRightGrip = CGPoint(x: 102, y: 70)
  public static let tugGripInDesignSpace = CGPoint(
    x: 102,
    y: AttachmentPose.standing.anchor.y + 100 * handHeightRatio)

  public static let tugGripsInDesignSpace = [CGPoint(x: 83, y: 52), tugGripInDesignSpace]

  public static func requiredHeadroom(for scene: PlayfulSceneDefinition, size: Double) -> Double {
    let authored = scene.clearanceAbove * size
    guard scene.phases.contains(where: { [.sign, .score, .letter].contains($0.prop) }) else {
      return authored
    }
    return max(authored, size * signHeightRatio + messageHeightAllowance)
  }

  public static func parachuteStringAnchor(for grip: CGPoint) -> CGPoint {
    let offset = CGPoint(
      x: grip.x - AttachmentPose.standing.anchor.x,
      y: grip.y - AttachmentPose.standing.anchor.y)
    return CGPoint(
      x: (offset.x / (referenceSize * parachuteWidthRatio) + 0.5) * parachuteTemplateSize.width,
      y: (offset.y - referenceSize * handHeightRatio) / (referenceSize * parachuteHeightRatio)
        * parachuteTemplateSize.height)
  }

  public struct Request: Sendable {
    public let prop: PlayfulSceneDefinition.Prop
    public let frames: [PlayfulSceneSession.Frame]
    public let plan: PlayfulScenePlan
    public let textSize: CGSize
    public let owner: PlayfulSceneDefinition.Role
    public let progress: Double

    public init(
      prop: PlayfulSceneDefinition.Prop, frames: [PlayfulSceneSession.Frame],
      plan: PlayfulScenePlan, textSize: CGSize,
      owner: PlayfulSceneDefinition.Role = .lead, progress: Double = 0
    ) {
      self.prop = prop
      self.frames = frames
      self.plan = plan
      self.textSize = textSize
      self.owner = owner
      self.progress = progress
    }
  }

  public struct RopeGeometry: Equatable, Sendable {
    public let strand: CGRect
    public let cornerStart: CGPoint
    public let cornerEnd: CGPoint
    public let clipHeight: Double

    public var cornerPath: CGPath {
      let bendRadius = 8.0
      let path = CGMutablePath()
      path.move(to: cornerStart)
      path.addLine(to: CGPoint(x: cornerEnd.x - bendRadius, y: cornerStart.y))
      path.addQuadCurve(to: cornerEnd, control: CGPoint(x: cornerEnd.x, y: cornerStart.y))
      return path
    }
  }

  public static func rope(
    in frame: CGRect, actor: PlayfulSceneSession.Frame, window: CGRect,
    retraction: Double = 0
  )
    -> RopeGeometry
  {
    let size = actor.actor.participant.surface.presentationSize
    let offset = AttachmentPose.hangingRight.contactOffset(from: .standing, size: size)
    let anchor = actor.actor.point(for: .outside, pose: .hangingRight)
    let grip = CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y)
    let cornerStart = CGPoint(x: window.maxX - 24 - frame.minX, y: window.maxY + 1.5 - frame.minY)
    let cornerEnd = CGPoint(x: grip.x - frame.minX, y: cornerStart.y - 8)
    let end =
      actor.actor.point(for: .below, pose: .hangingRight).y + offset.y - size * ropeTailRatio
    let restingBottom = max(0, min(cornerEnd.y, end - frame.minY))
    let top = max(cornerEnd.y, grip.y - frame.minY)
    let bottom = restingBottom + max(0, min(retraction, 1)) * (top - restingBottom)
    return RopeGeometry(
      strand: CGRect(x: cornerEnd.x - 1.5, y: bottom, width: 3, height: max(3, top - bottom)),
      cornerStart: cornerStart, cornerEnd: cornerEnd, clipHeight: window.maxY - frame.minY)
  }

  public static func ropeTopFrame(actor: PlayfulSceneSession.Frame, plan: PlayfulScenePlan)
    -> CGRect?
  {
    guard let window = plan.window else { return nil }
    let size = actor.actor.participant.surface.presentationSize
    let offset = AttachmentPose.hangingRight.contactOffset(from: .standing, size: size)
    let gripX = actor.actor.point(for: .outside, pose: .hangingRight).x + offset.x
    let frame = CGRect(
      x: window.maxX - 26, y: window.maxY, width: gripX - window.maxX + 32,
      height: ropeAnchorBackingHeight)
    return plan.visibleFrame.contains(frame) ? frame : nil
  }

  public static func frame(for request: Request) -> CGRect? {
    guard request.prop != .none,
      let lead = request.frames.first(where: { $0.actor.role == request.owner })
    else { return nil }
    let size = lead.actor.participant.surface.presentationSize
    let origin = lead.position
    let result: CGRect
    switch request.prop {
    case .none: return nil
    case .rope:
      guard let partner = request.frames.first(where: { $0.actor.role == .partner }) else {
        return nil
      }
      let first = CGPoint(x: origin.x + size * handReachRatio, y: origin.y + size * handHeightRatio)
      let last = CGPoint(
        x: partner.position.x - size * handReachRatio,
        y: partner.position.y + size * handHeightRatio)
      result = CGRect(
        x: min(first.x, last.x), y: min(first.y, last.y),
        width: abs(last.x - first.x), height: abs(last.y - first.y)
      ).insetBy(dx: -ropeMargin, dy: -ropeMargin)
    case .campfire:
      let center = request.frames.reduce(0) { $0 + $1.position.x } / Double(request.frames.count)
      result = CGRect(
        x: center - fireSize.width / 2, y: origin.y, width: fireSize.width, height: fireSize.height)
    case .plane:
      result = PlayfulPlaneFlight.frame(
        origin: lead.actor.participant.position, size: size,
        visible: request.plan.visibleFrame, progress: request.progress)
    case .parachute:
      let parachuteSize = CGSize(
        width: size * parachuteWidthRatio, height: size * parachuteHeightRatio)
      result = CGRect(
        x: origin.x - parachuteSize.width / 2, y: origin.y + size * handHeightRatio,
        width: parachuteSize.width, height: parachuteSize.height)
    case .descentRope, .retractingRope:
      let gripOffset = AttachmentPose.hangingRight.contactOffset(from: .standing, size: size)
      let top = lead.actor.outside.y + ropeMargin / 2
      let bottom =
        lead.actor.point(for: .below, pose: .hangingRight).y + gripOffset.y - size * ropeTailRatio
      let edge = request.plan.window?.maxX ?? origin.x - ropeMargin / 2
      result = CGRect(
        x: edge, y: min(top, bottom),
        width: lead.actor.point(for: .outside, pose: .hangingRight).x + gripOffset.x - edge
          + ropeMargin / 2,
        height: max(ropeMargin, abs(top - bottom)))
    case .sign, .letter, .score:
      let proposedX = origin.x - request.textSize.width / 2
      let x = min(
        max(proposedX, request.plan.visibleFrame.minX),
        request.plan.visibleFrame.maxX - request.textSize.width)
      result = CGRect(
        x: x, y: origin.y + size * signHeightRatio,
        width: request.textSize.width, height: request.textSize.height)
    }
    guard request.plan.visibleFrame.contains(result),
      request.plan.window.map({ !$0.intersects(result) }) ?? true
    else { return nil }
    return result
  }
}
