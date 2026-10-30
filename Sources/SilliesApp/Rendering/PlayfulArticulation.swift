import QuartzCore

/// Shoulder, ankle, and neck pivots give authored poses weight without changing normal clips.
@MainActor
final class PlayfulArticulation {
  enum Hand { case left, right }
  private struct Joint {
    let layer: CALayer
    let bounds: CGRect
    let position: CGPoint
    let anchor: CGPoint
    let sceneAnchor: CGPoint

    func activate() {
      let origin = CGPoint(
        x: position.x - bounds.width * anchor.x,
        y: position.y - bounds.height * anchor.y)
      layer.anchorPoint = sceneAnchor
      layer.position = CGPoint(
        x: origin.x + bounds.width * sceneAnchor.x,
        y: origin.y + bounds.height * sceneAnchor.y)
    }

    func restore() {
      layer.bounds = bounds
      layer.anchorPoint = anchor
      layer.position = position
    }
  }
  private let joints: [Joint]
  private let rightArm: CALayer
  private let leftArm: CALayer

  init(rig: CharacterRig) {
    rightArm = rig.rightArm
    leftArm = rig.leftArm
    joints = [
      (rig.head, CGPoint(x: 0.5, y: 0.18)),
      (rig.leftArm, CGPoint(x: 0.5, y: 0.88)), (rig.rightArm, CGPoint(x: 0.5, y: 0.88)),
      (rig.leftFoot, CGPoint(x: 0.5, y: 0.9)), (rig.rightFoot, CGPoint(x: 0.5, y: 0.9)),
    ].map {
      Joint(
        layer: $0.0, bounds: $0.0.bounds, position: $0.0.position,
        anchor: $0.0.anchorPoint, sceneAnchor: $0.1)
    }
  }

  func activate() { for joint in joints { joint.activate() } }
  func restore() { for joint in joints { joint.restore() } }

  /// Keep a shared prop's grip fixed while the torso and head supply the effort.
  func holdProp(at point: CGPoint, hand: Hand, angle: CGFloat) {
    let arm = hand == .left ? leftArm : rightArm
    guard let joint = joints.first(where: { $0.layer === arm }) else { return }
    let localHandY = joint.bounds.height * 0.22
    let reach = localHandY - joint.bounds.height * joint.sceneAnchor.y
    let shoulder = CGPoint(
      x: joint.position.x + joint.bounds.width * (joint.sceneAnchor.x - joint.anchor.x),
      y: joint.position.y + joint.bounds.height * (joint.sceneAnchor.y - joint.anchor.y))
    let translation = CATransform3DMakeTranslation(
      point.x - shoulder.x + reach * sin(angle),
      point.y - shoulder.y - reach * cos(angle), 0)
    arm.transform = CATransform3DRotate(translation, angle, 0, 0, 1)
  }
}
