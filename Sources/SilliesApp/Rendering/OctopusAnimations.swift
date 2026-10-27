import QuartzCore
import SilliesCore

@MainActor
enum OctopusAnimations {
  static let wave: AnimationID = "bloop.wave"
  static let stretch: AnimationID = "bloop.stretch"
  private static let armCurls = [
    RigAnimation.Oscillation(keyPath: "transform.rotation.z", from: -0.20, to: 0.12, duration: 0.6),
    RigAnimation.Oscillation(keyPath: "transform.rotation.z", from: 0.10, to: -0.18, duration: 0.8),
    RigAnimation.Oscillation(keyPath: "transform.rotation.z", from: -0.12, to: 0.20, duration: 0.7),
    RigAnimation.Oscillation(keyPath: "transform.rotation.z", from: 0.18, to: -0.10, duration: 0.9),
  ]
  private static let greeting = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: 0.3, to: 1.0, duration: 0.22)
  private static let elastic = RigAnimation.Sequence(
    keyPath: "transform.scale.y", values: [1, 1.20, 0.94, 1.04, 1],
    times: [0, 0.18, 0.45, 0.72, 1], duration: 0.8)
  private static let splat = RigAnimation.Sequence(
    keyPath: "transform.scale.y", values: [1, 0.68, 1.13, 1], times: [0, 0.2, 0.55, 1],
    duration: 0.6)
  private static let spread = RigAnimation.Sequence(
    keyPath: "transform.scale.x", values: [1, 1.16, 0.94, 1], times: [0, 0.2, 0.55, 1],
    duration: 0.6)

  static func register(in library: AnimationLibrary) {
    library.register(.idle, characterID: "bloop", clip: curlArms)
    library.register(.walk, characterID: "bloop") { rig in
      CreatureMotion.steps(rig)
      curlArms(rig)
    }
    library.register(.hang, characterID: "bloop", clip: curlArms)
    library.register(.climb, characterID: "bloop") { rig in
      CreatureMotion.climb(rig)
      curlArms(rig)
    }
    library.register(.hangCatch, characterID: "bloop") { rig in
      CreatureMotion.catchLedge(rig)
      curlArms(rig)
    }
    library.register(.land, characterID: "bloop") { rig in
      RigAnimation.play(rig.stage, splat)
      RigAnimation.play(rig.stage, spread)
    }
    library.registerSignature(wave, characterID: "bloop") { rig in
      curlArms(rig)
      RigAnimation.oscillate(rig.rightArm, greeting)
      rig.delight.opacity = 1
    }
    library.registerSignature(stretch, characterID: "bloop") { rig in
      RigAnimation.play(rig.stage, elastic)
      curlArms(rig)
    }
  }

  private static func curlArms(_ rig: CharacterRig) {
    guard let octopus = rig as? OctopusRig else { return }
    CreatureMotion.blink(rig)
    for (arm, motion) in zip(octopus.rearArms, armCurls) { RigAnimation.oscillate(arm, motion) }
  }
}
