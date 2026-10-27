import QuartzCore
import SilliesCore

@MainActor
enum PenguinAnimations {
  static let slide: AnimationID = "pebble.slide"
  private static let bow = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: -0.045, to: 0.045, duration: 1.4)
  private static let leftFlap = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: -0.7, to: -0.2, duration: 0.16)
  private static let rightFlap = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: 0.7, to: 0.2, duration: 0.16)
  private static let lean = RigAnimation.Sequence(
    keyPath: "transform.rotation.z", values: [0, -0.18, -0.18, 0], times: [0, 0.2, 0.7, 1],
    duration: 1.3)
  private static let flatten = RigAnimation.Sequence(
    keyPath: "transform.scale.y", values: [1, 0.74, 0.74, 1], times: [0, 0.2, 0.7, 1], duration: 1.3
  )
  private static let scoot = RigAnimation.Sequence(
    keyPath: "transform.translation.x", values: [0, 5, -3, 0], times: [0, 0.35, 0.7, 1],
    duration: 1.3)

  static func register(in library: AnimationLibrary) {
    library.register(.idle, characterID: "pebble", clip: straightenBow)
    library.register(.walk, characterID: "pebble") { rig in
      CreatureMotion.waddle(rig)
      straightenBow(rig)
    }
    library.register(.balance, characterID: "pebble", clip: windmill)
    library.register(.brace, characterID: "pebble", clip: windmill)
    library.register(.hang, characterID: "pebble", clip: straightenBow)
    library.register(.climb, characterID: "pebble") { rig in
      CreatureMotion.climb(rig)
      straightenBow(rig)
    }
    library.register(.hangCatch, characterID: "pebble") { rig in
      CreatureMotion.catchLedge(rig)
      straightenBow(rig)
    }
    library.registerSignature(slide, characterID: "pebble") { rig in
      RigAnimation.play(rig.stage, lean)
      RigAnimation.play(rig.stage, flatten)
      RigAnimation.play(rig.stage, scoot)
      windmill(rig)
    }
  }

  private static func straightenBow(_ rig: CharacterRig) {
    guard let penguin = rig as? PenguinRig else { return }
    CreatureMotion.blink(rig)
    RigAnimation.oscillate(penguin.bowTie, bow)
  }

  private static func windmill(_ rig: CharacterRig) {
    RigAnimation.oscillate(rig.leftArm, leftFlap)
    RigAnimation.oscillate(rig.rightArm, rightFlap)
  }
}
