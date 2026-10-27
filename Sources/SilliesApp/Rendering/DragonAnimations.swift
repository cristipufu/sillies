import QuartzCore
import SilliesCore

@MainActor
enum DragonAnimations {
  static let sneeze: AnimationID = "taro.sneeze"
  static let flutter: AnimationID = "taro.flutter"
  private static let leftRest = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: -0.04, to: 0.08, duration: 1.5)
  private static let rightRest = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: 0.04, to: -0.08, duration: 1.5)
  private static let tail = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: -0.08, to: 0.08, duration: 1.2)
  private static let leftFlap = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: -0.3, to: 0.18, duration: 0.14)
  private static let rightFlap = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: 0.3, to: -0.18, duration: 0.14)
  private static let hiccup = RigAnimation.Sequence(
    keyPath: "transform.scale.y", values: [1, 0.92, 1.12, 0.96, 1],
    times: [0, 0.35, 0.45, 0.65, 1], duration: 1.2)
  private static let sparkFlash = RigAnimation.Sequence(
    keyPath: "opacity", values: [0, 0, 1, 0], times: [0, 0.4, 0.47, 1], duration: 1.2)
  private static let sparkDrift = RigAnimation.Sequence(
    keyPath: "transform.translation.x", values: [0, 0, 4, 7], times: [0, 0.4, 0.65, 1],
    duration: 1.2)

  static func register(in library: AnimationLibrary) {
    library.register(.idle, characterID: "taro", clip: restWings)
    library.register(.walk, characterID: "taro") { rig in
      CreatureMotion.steps(rig)
      restWings(rig)
    }
    library.register(.hang, characterID: "taro", clip: restWings)
    library.register(.climb, characterID: "taro") { rig in
      CreatureMotion.climb(rig)
      flap(rig)
    }
    library.register(.hangCatch, characterID: "taro") { rig in
      CreatureMotion.catchLedge(rig)
      flap(rig)
    }
    library.registerSignature(flutter, characterID: "taro", clip: flap)
    library.registerSignature(sneeze, characterID: "taro") { rig in
      guard let dragon = rig as? DragonRig else { return }
      RigAnimation.play(rig.stage, hiccup)
      RigAnimation.play(dragon.spark, sparkFlash)
      RigAnimation.play(dragon.spark, sparkDrift)
      restWings(rig)
    }
  }

  private static func restWings(_ rig: CharacterRig) {
    guard let dragon = rig as? DragonRig else { return }
    CreatureMotion.blink(rig)
    RigAnimation.oscillate(dragon.leftWing, leftRest)
    RigAnimation.oscillate(dragon.rightWing, rightRest)
    RigAnimation.oscillate(dragon.tail, tail)
  }

  private static func flap(_ rig: CharacterRig) {
    guard let dragon = rig as? DragonRig else { return }
    RigAnimation.oscillate(dragon.leftWing, leftFlap)
    RigAnimation.oscillate(dragon.rightWing, rightFlap)
    RigAnimation.oscillate(dragon.tail, tail)
  }
}
