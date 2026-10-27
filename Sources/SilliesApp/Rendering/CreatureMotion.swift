import QuartzCore

/// Shared limb mechanics; character clips compose these with their own local details.
@MainActor
enum CreatureMotion {
  private static let leftStep = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: -0.22, to: 0.22, duration: 0.3)
  private static let rightStep = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: 0.22, to: -0.22, duration: 0.3)
  private static let sway = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: -0.045, to: 0.045, duration: 0.3)
  private static let climbBody = RigAnimation.Sequence(
    keyPath: "transform.translation.y", values: [0, -2, 3, 0], times: [0, 0.2, 0.6, 1],
    duration: 0.7)
  private static let lowerHand = RigAnimation.Oscillation(
    keyPath: "transform.translation.y", from: 0, to: 6, duration: 0.35)
  private static let catchBody = RigAnimation.Sequence(
    keyPath: "transform.translation.y", values: [0, -6, 2, 0], times: [0, 0.2, 0.6, 1],
    duration: 0.6)
  private static let blink = RigAnimation.Sequence(
    keyPath: "transform.scale.y", values: [1, 1, 0.1, 1, 1], times: [0, 0.78, 0.82, 0.86, 1],
    duration: 5)

  static func blink(_ rig: CharacterRig) { RigAnimation.loop(rig.eyes, blink) }

  static func steps(_ rig: CharacterRig) {
    RigAnimation.oscillate(rig.leftFoot, leftStep)
    RigAnimation.oscillate(rig.rightFoot, rightStep)
  }

  static func waddle(_ rig: CharacterRig) {
    steps(rig)
    RigAnimation.oscillate(rig.stage, sway)
  }

  static func climb(_ rig: CharacterRig) {
    steps(rig)
    RigAnimation.loop(rig.stage, climbBody)
    RigAnimation.oscillate(rig.secondaryGrip, lowerHand)
  }

  static func catchLedge(_ rig: CharacterRig) {
    RigAnimation.play(rig.stage, catchBody)
  }
}
