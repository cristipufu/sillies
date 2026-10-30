import AppKit
import QuartzCore
import SilliesCore

/// Both palms are authored together so the rope grip and shove contact cannot drift apart.
@MainActor
final class PlayfulContactArtwork {
  private enum Shove {
    static let duration = 0.9
    static let restingReach = 92.0
    static let times: [NSNumber] = [0, 0.18, 0.35, 0.55, 1]
    static let reach: [CGFloat] = [88, 84, 116, 121, 92]
    static let heights: [CGFloat] = [58, 73]
  }
  private static let clamberSampleCount = 40
  let layer = CALayer()
  private let arms: [CharacterFlexibleArmArtwork]
  var gripPoints: [CGPoint] { arms.map { $0.hand.position } }

  init(rig: CharacterRig) {
    layer.frame = rig.stage.bounds
    rig.stage.addSublayer(layer)
    arms = [
      CharacterFlexibleArmArtwork(source: rig.leftArm, parent: layer, rig: rig, depth: .foreground),
      CharacterFlexibleArmArtwork(
        source: rig.rightArm, parent: layer, rig: rig, depth: .background),
    ]
    reset()
  }

  func gripRope() {
    layer.opacity = 1
    for (arm, grip) in zip(arms, PlayfulPropLayout.tugGripsInDesignSpace) { arm.pose(at: grip) }
  }

  func shove() {
    layer.opacity = 1
    for (arm, height) in zip(arms, Shove.heights) {
      let grips = Shove.reach.map { CGPoint(x: $0, y: height) }
      arm.pose(at: CGPoint(x: Shove.restingReach, y: height))
      let paths = grips.map { arm.path(to: $0) }
      animate(arm.outline, key: "path", values: paths)
      animate(arm.sleeve, key: "path", values: paths)
      animate(arm.hand, key: "position", values: grips.map { NSValue(point: $0) })
    }
  }

  func clamber(motion: PlayfulClamberMotion, duration: Double) {
    layer.opacity = 1
    let samples = (0...Self.clamberSampleCount).map { Double($0) / Double(Self.clamberSampleCount) }
    let times = samples.map { NSNumber(value: $0) }
    let grips = samples.map { motion.handPoints(at: $0) }
    for (index, arm) in arms.enumerated() {
      let points = grips.map { $0[index] }
      arm.pose(at: motion.handPoints(at: 1)[index])
      let paths = points.map { arm.path(to: $0) }
      let motion = Timing(times: times, duration: duration, curve: .linear)
      animate(arm.outline, key: "path", values: paths, timing: motion)
      animate(arm.sleeve, key: "path", values: paths, timing: motion)
      animate(arm.hand, key: "position", values: points.map { NSValue(point: $0) }, timing: motion)
    }
  }

  func reset() {
    layer.opacity = 0
    for arm in arms { arm.reset() }
  }

  private struct Timing {
    let times: [NSNumber]
    let duration: Double
    let curve: CAMediaTimingFunctionName
    static let shove = Timing(times: Shove.times, duration: Shove.duration, curve: .easeInEaseOut)
  }

  private func animate(_ target: CALayer, key: String, values: [Any], timing: Timing = .shove) {
    let animation = CAKeyframeAnimation(keyPath: key)
    animation.values = values
    animation.keyTimes = timing.times
    animation.duration = timing.duration
    animation.timingFunctions = timing.times.dropFirst().map { _ in
      CAMediaTimingFunction(name: timing.curve)
    }
    target.add(animation, forKey: key)
  }
}
