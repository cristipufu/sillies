import QuartzCore
import SilliesCore

@MainActor
enum HedgehogAnimations {
  static let curl: AnimationID = "nib.curl"
  private static let look = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: -0.035, to: 0.045, duration: 1.8)
  private static let leftStep = RigAnimation.Sequence(
    keyPath: "transform.translation.y", values: [0, 3, 0, 0, 0], times: [0, 0.15, 0.3, 0.7, 1],
    duration: 0.9)
  private static let rightStep = RigAnimation.Sequence(
    keyPath: "transform.translation.y", values: [0, 0, 0, 3, 0], times: [0, 0.3, 0.5, 0.7, 1],
    duration: 0.9)
  private static let shell = RigAnimation.Sequence(
    keyPath: "opacity", values: [0, 1, 1, 0], times: [0, 0.18, 0.7, 1], duration: 1.8)
  private static let tuck = RigAnimation.Sequence(
    keyPath: "opacity", values: [1, 0, 0, 1], times: [0, 0.18, 0.7, 1], duration: 1.8)
  private static let rock = RigAnimation.Sequence(
    keyPath: "transform.rotation.z", values: [0, -0.14, 0.12, 0], times: [0, 0.3, 0.6, 1],
    duration: 1.8)

  static func register(in library: AnimationLibrary) {
    library.register(.idle, characterID: "nib", clip: inspect)
    library.register(.walk, characterID: "nib") { rig in
      RigAnimation.loop(rig.leftFoot, leftStep)
      RigAnimation.loop(rig.rightFoot, rightStep)
      inspect(rig)
    }
    library.register(.hang, characterID: "nib", clip: inspect)
    library.register(.climb, characterID: "nib") { rig in
      CreatureMotion.climb(rig)
      inspect(rig)
    }
    library.register(.hangCatch, characterID: "nib") { rig in
      CreatureMotion.catchLedge(rig)
      inspect(rig)
    }
    library.registerSignature(curl, characterID: "nib") { rig in
      guard let hedgehog = rig as? HedgehogRig else { return }
      RigAnimation.play(hedgehog.curlShell, shell)
      RigAnimation.play(hedgehog.curlShell, rock)
      for part in [rig.head, rig.leftArm, rig.rightArm, rig.leftFoot, rig.rightFoot] {
        RigAnimation.play(part, tuck)
      }
    }
  }

  private static func inspect(_ rig: CharacterRig) {
    CreatureMotion.blink(rig)
    RigAnimation.oscillate(rig.head, look)
  }
}
