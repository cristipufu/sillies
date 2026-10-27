import QuartzCore
import SilliesCore

@MainActor
enum GhostAnimations {
  static let shy: AnimationID = "boo.shy"
  private static let float = RigAnimation.Oscillation(
    keyPath: "transform.translation.y", from: 0, to: 4, duration: 1.4)
  private static let hem = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: -0.12, to: 0.12, duration: 0.8)
  private static let drift = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: -0.035, to: 0.035, duration: 1)
  private static let hide = RigAnimation.Sequence(
    keyPath: "opacity", values: [0, 1, 1, 0], times: [0, 0.18, 0.72, 1], duration: 1.5)
  private static let peek = RigAnimation.Sequence(
    keyPath: "transform.translation.y", values: [-12, 0, -2, -12], times: [0, 0.18, 0.72, 1],
    duration: 1.5)

  static func register(in library: AnimationLibrary) {
    library.register(.idle, characterID: "boo", clip: hover)
    library.register(.walk, characterID: "boo", clip: driftAlong)
    library.register(.hang, characterID: "boo", clip: hover)
    library.register(.climb, characterID: "boo") { rig in
      CreatureMotion.climb(rig)
      flutterHem(rig)
    }
    library.register(.hangCatch, characterID: "boo") { rig in
      CreatureMotion.catchLedge(rig)
      flutterHem(rig)
    }
    library.registerSignature(shy, characterID: "boo") { rig in
      guard let ghost = rig as? GhostRig else { return }
      RigAnimation.play(ghost.sheetFold, hide)
      RigAnimation.play(ghost.sheetFold, peek)
      flutterHem(ghost)
    }
  }

  private static func hover(_ rig: CharacterRig) {
    CreatureMotion.blink(rig)
    RigAnimation.oscillate(rig.stage, float)
    flutterHem(rig)
  }

  private static func driftAlong(_ rig: CharacterRig) {
    hover(rig)
    RigAnimation.oscillate(rig.head, drift)
  }

  private static func flutterHem(_ rig: CharacterRig) {
    RigAnimation.oscillate(rig.leftFoot, hem)
    RigAnimation.oscillate(rig.rightFoot, drift)
  }
}
