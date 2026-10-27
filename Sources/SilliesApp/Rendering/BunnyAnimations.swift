import QuartzCore
import SilliesCore

@MainActor
enum BunnyAnimations {
  static let listen: AnimationID = "mallow.listen"
  private static let leftRest = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: -0.035, to: 0.06, duration: 1.5)
  private static let rightRest = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: 0.07, to: -0.07, duration: 1.9)
  private static let twitch = RigAnimation.Sequence(
    keyPath: "transform.scale.y", values: [1, 1, 0.65, 1, 0.7, 1, 1],
    times: [0, 0.6, 0.65, 0.7, 0.75, 0.8, 1], duration: 3.2)
  private static let bounce = RigAnimation.Sequence(
    keyPath: "transform.translation.y", values: [0, 0, 5, 0], times: [0, 0.2, 0.55, 1],
    duration: 0.55)
  private static let perk = RigAnimation.Sequence(
    keyPath: "transform.rotation.z", values: [0, -0.23, -0.23, 0], times: [0, 0.15, 0.65, 1],
    duration: 1.6)
  private static let lag = RigAnimation.Sequence(
    keyPath: "transform.rotation.z", values: [0, 0, 0.3, 0], times: [0, 0.25, 0.6, 1], duration: 1.6
  )

  static func register(in library: AnimationLibrary) {
    library.register(.idle, characterID: "mallow", clip: restEars)
    library.register(.walk, characterID: "mallow") { rig in
      CreatureMotion.steps(rig)
      RigAnimation.loop(rig.stage, bounce)
      restEars(rig)
    }
    library.register(.listen, characterID: "mallow", clip: prickEars)
    library.register(.hang, characterID: "mallow", clip: restEars)
    library.register(.climb, characterID: "mallow") { rig in
      CreatureMotion.climb(rig)
      restEars(rig)
    }
    library.register(.hangCatch, characterID: "mallow") { rig in
      CreatureMotion.catchLedge(rig)
      prickEars(rig)
    }
    library.registerSignature(listen, characterID: "mallow", clip: prickEars)
  }

  private static func restEars(_ rig: CharacterRig) {
    guard let bunny = rig as? BunnyRig else { return }
    CreatureMotion.blink(rig)
    RigAnimation.oscillate(bunny.leftEar, leftRest)
    RigAnimation.oscillate(bunny.rightEar, rightRest)
    RigAnimation.loop(bunny.nose, twitch)
  }

  private static func prickEars(_ rig: CharacterRig) {
    guard let bunny = rig as? BunnyRig else { return }
    RigAnimation.loop(bunny.leftEar, perk)
    RigAnimation.loop(bunny.rightEar, lag)
    RigAnimation.loop(bunny.nose, twitch)
  }
}
