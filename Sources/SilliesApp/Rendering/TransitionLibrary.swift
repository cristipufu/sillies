import QuartzCore
import SilliesCore

struct TransitionContext {
  let kind: TransitionKind
  let duration: Double
  let fromOpacity: Double
  let fromScale: Double

  var targetOpacity: Double { kind == .exit ? 0 : 1 }
}

/// Finite presentation clips are independent of looping character behavior clips.
@MainActor
final class TransitionLibrary {
  typealias Clip = @MainActor (TransitionContext) -> CAAnimation
  private var clips: [AnimationID: Clip] = [:]

  init() {
    register(.appear) { context in
      Self.group(
        [
          Self.opacity(context),
          Self.values("transform.scale", [context.fromScale, 1.06, 1], [0, 0.65, 1]),
        ], duration: context.duration)
    }
    register(.disappear) { context in
      Self.group(
        [
          Self.opacity(context),
          Self.values("transform.scale", [context.fromScale, 0.84], [0, 1]),
        ], duration: context.duration)
    }
    register("fade") { context in
      Self.group([Self.opacity(context)], duration: context.duration)
    }
  }

  func register(_ id: AnimationID, clip: @escaping Clip) { clips[id] = clip }
  func contains(_ id: AnimationID) -> Bool { clips[id] != nil }

  func make(_ id: AnimationID, context: TransitionContext) -> CAAnimation? {
    clips[id]?(context)
  }

  private static func opacity(_ context: TransitionContext) -> CAKeyframeAnimation {
    values("opacity", [context.fromOpacity, context.targetOpacity], [0, 1])
  }

  private static func values(_ key: String, _ values: [Double], _ times: [NSNumber])
    -> CAKeyframeAnimation
  {
    let animation = CAKeyframeAnimation(keyPath: key)
    animation.values = values
    animation.keyTimes = times
    return animation
  }

  private static func group(_ animations: [CAAnimation], duration: Double) -> CAAnimationGroup {
    for animation in animations { animation.duration = duration }
    let group = CAAnimationGroup()
    group.animations = animations
    group.duration = duration
    group.timingFunction = CAMediaTimingFunction(name: .easeOut)
    return group
  }
}
