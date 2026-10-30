import AppKit
import QuartzCore

/// Broom, fingers, and flexible forearms share one authored cycle; no per-frame work is needed.
@MainActor
final class PlayfulSweepArtwork {
  private enum Motion {
    static let duration = 1.3
    static let times: [NSNumber] = [0, 0.25, 0.5, 0.75, 1]
    static let brushX: [CGFloat] = [90, 96, 112, 106, 90]
    static let angles: [CGFloat] = [0.40, 0.25, 0.38, 0.50, 0.40]
    static let floor: CGFloat = 20
  }
  private struct Arm {
    let gripHeight: CGFloat
    let artwork: CharacterFlexibleArmArtwork
  }
  let layer = CALayer()
  private let broom = CALayer()
  private let handle = CALayer()
  private var arms: [Arm] = []

  init(rig: CharacterRig) {
    layer.frame = rig.stage.bounds
    layer.name = ArtworkHitTester.decorationName
    rig.stage.addSublayer(layer)
    configureBrush(rig)
    arms = [
      makeArm(rig.leftArm, height: 39, rig: rig), makeArm(rig.rightArm, height: 18, rig: rig),
    ]
    applyRestingPose()
    reset()
  }

  func show() {
    layer.opacity = 1
    applyRestingPose()
  }

  func play() {
    show()
    animate(
      broom, key: "position",
      values: Motion.brushX.map { NSValue(point: CGPoint(x: $0, y: Motion.floor)) })
    animate(handle, key: "transform.rotation.z", values: Motion.angles)
    for arm in arms {
      let grips = Motion.brushX.indices.map { grip(for: arm, sample: $0) }
      let paths = grips.map { arm.artwork.path(to: $0) }
      animate(arm.artwork.outline, key: "path", values: paths)
      animate(arm.artwork.sleeve, key: "path", values: paths)
      animate(arm.artwork.hand, key: "position", values: grips.map { NSValue(point: $0) })
      animate(arm.artwork.hand, key: "transform.rotation.z", values: Motion.angles)
    }
  }

  func reset() {
    layer.opacity = 0
    broom.removeAllAnimations()
    handle.removeAllAnimations()
    for arm in arms {
      arm.artwork.reset()
    }
  }

  private func configureBrush(_ rig: CharacterRig) {
    broom.bounds = CGRect(x: -20, y: -4, width: 40, height: 88)
    broom.anchorPoint = CGPoint(x: 0.5, y: 4.0 / 88)
    layer.addSublayer(broom)
    handle.position = CGPoint(x: 0, y: 18)
    broom.addSublayer(handle)
    rig.line(
      on: handle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 60)], color: "946C4F", width: 5)
    rig.line(
      on: handle, points: [CGPoint(x: -1, y: 2), CGPoint(x: -1, y: 58)], color: "DDC09B", width: 1.5
    )
    let fan = CGMutablePath()
    fan.move(to: CGPoint(x: -6, y: 18))
    fan.addLine(to: CGPoint(x: 6, y: 18))
    fan.addLine(to: CGPoint(x: 16, y: 2))
    fan.addQuadCurve(to: CGPoint(x: -16, y: 2), control: CGPoint(x: 0, y: -2))
    fan.closeSubpath()
    rig.shape(on: broom, path: fan, fill: "E9C28A", stroke: "AA8055", lineWidth: 1)
    for x in stride(from: -12.0, through: 12, by: 4) {
      rig.line(
        on: broom, points: [CGPoint(x: x * 0.4, y: 16), CGPoint(x: x, y: 2)], color: "B98D58",
        width: 0.8)
    }
    rig.pill(on: broom, CGRect(x: -7, y: 16, width: 14, height: 5), "A57779", radius: 2)
  }

  private func makeArm(_ source: CALayer, height: CGFloat, rig: CharacterRig) -> Arm {
    Arm(
      gripHeight: height,
      artwork: CharacterFlexibleArmArtwork(source: source, parent: layer, rig: rig))
  }

  private func applyRestingPose() {
    broom.position = CGPoint(x: Motion.brushX[0], y: Motion.floor)
    handle.transform = CATransform3DMakeRotation(Motion.angles[0], 0, 0, 1)
    for arm in arms {
      let point = grip(for: arm, sample: 0)
      arm.artwork.pose(at: point, angle: Motion.angles[0])
    }
  }

  private func grip(for arm: Arm, sample: Int) -> CGPoint {
    CGPoint(
      x: Motion.brushX[sample] - sin(Motion.angles[sample]) * arm.gripHeight,
      y: Motion.floor + 18 + cos(Motion.angles[sample]) * arm.gripHeight)
  }

  private func animate(_ target: CALayer, key: String, values: [Any]) {
    let animation = CAKeyframeAnimation(keyPath: key)
    animation.values = values
    animation.keyTimes = Motion.times
    animation.duration = Motion.duration
    animation.repeatCount = .infinity
    animation.timingFunctions = Motion.times.dropFirst().map { _ in
      CAMediaTimingFunction(name: .easeInEaseOut)
    }
    target.add(animation, forKey: key)
  }
}
