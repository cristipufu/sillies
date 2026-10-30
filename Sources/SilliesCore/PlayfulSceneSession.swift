import CoreGraphics
import Foundation

/// A single finite timeline owns the entire cast; sampling never changes the plan.
public struct PlayfulSceneSession: Sendable {
  public struct Frame: Sendable {
    public let actor: PlayfulScenePlan.Actor
    public let position: CGPoint
    public let animation: AnimationID
    public let edge: PerchSurface.Edge
    public let facingRight: Bool
    public let duration: Double
    public let pose: AttachmentPose
    public var gripPoint: CGPoint {
      let offset = pose.contactOffset(
        from: .standing, size: actor.participant.surface.presentationSize)
      return CGPoint(x: position.x + offset.x, y: position.y + offset.y)
    }
  }
  public let plan: PlayfulScenePlan
  public let startedAt: Double
  public private(set) var isCancelled = false
  public var endsAt: Double { startedAt + plan.definition.duration }

  public init(plan: PlayfulScenePlan, at time: Double) {
    self.plan = plan
    startedAt = time
  }

  public func phaseIndex(at time: Double) -> Int? {
    guard !isCancelled, time >= startedAt, time < endsAt else { return nil }
    var boundary = startedAt
    for (index, phase) in plan.definition.phases.enumerated() {
      boundary += phase.duration
      if time < boundary { return index }
    }
    return nil
  }

  public func phaseStart(_ index: Int) -> Double {
    startedAt + plan.definition.phases.prefix(index).reduce(0) { $0 + $1.duration }
  }

  public func frames(at time: Double) -> [Frame] {
    guard let index = phaseIndex(at: time) else { return [] }
    let phase = plan.definition.phases[index]
    let progress = min(max((time - phaseStart(index)) / phase.duration, 0), 1)
    return plan.actors.compactMap { actor in
      guard let cue = phase.cues.first(where: { $0.role == actor.role }) else { return nil }
      let previous =
        index == 0 ? nil : plan.definition.phases[index - 1].cues.first { $0.role == actor.role }
      let movementStart = cue.movementStart ?? 0
      let movement = max(0, (progress - movementStart) / (1 - movementStart))
      let eased = movement * movement * (3 - 2 * movement)
      let pose = cue.pose ?? .standing
      let from = actor.point(for: previous?.destination ?? .home, pose: previous?.pose ?? .standing)
      let to = actor.point(for: cue.destination, pose: pose)
      let sway =
        phase.motion?.offset(at: progress, size: actor.participant.surface.presentationSize) ?? 0
      let pullUp = cue.travel == .cornerPullUp ? PlayfulClamberMotion(actor: actor) : nil
      let point =
        pullUp?.position(at: progress)
        ?? CGPoint(
          x: from.x + (to.x - from.x) * eased + sway, y: from.y + (to.y - from.y) * eased)
      let isDescending = cue.destination == .below || previous?.destination == .below
      return Frame(
        actor: actor, position: point,
        animation: actor.participant.profile.animation(for: cue.animation),
        edge: pullUp?.edge(at: progress)
          ?? (isDescending || pose.isHanging || previous?.pose?.isHanging == true
            ? .right : actor.participant.surface.edge),
        facingRight: cue.facing.map { $0 == .right }
          ?? (phase.prop == .plane
            ? PlayfulPlaneFlight.facesRight(
              origin: actor.participant.position, visible: plan.visibleFrame)
            : abs(to.x - from.x) > 0.01
              ? to.x > from.x : (!isDescending && actor.role == .lead)),
        duration: phase.duration, pose: pose)
    }
  }

  public mutating func cancel() { isCancelled = true }
}
