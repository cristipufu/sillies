import QuartzCore
import SilliesCore

@MainActor
enum AxolotlAnimations {
  static let flutter: AnimationID = "pip.flutter"
  private static let leftRest = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: -0.06, to: 0.06, duration: 1.1)
  private static let rightRest = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: 0.06, to: -0.06, duration: 1.3)
  private static let leftFlutter = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: -0.16, to: 0.14, duration: 0.18)
  private static let rightFlutter = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: 0.16, to: -0.14, duration: 0.18)
  private static let swish = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: -0.09, to: 0.12, duration: 0.6)

  static func register(in library: AnimationLibrary) {
    library.register(.idle, characterID: "pip", clip: breathe)
    library.register(.walk, characterID: "pip") { rig in
      CreatureMotion.steps(rig)
      breathe(rig)
    }
    library.register(.hang, characterID: "pip", clip: breathe)
    library.register(.climb, characterID: "pip") { rig in
      CreatureMotion.climb(rig)
      breathe(rig)
    }
    library.register(.hangCatch, characterID: "pip") { rig in
      CreatureMotion.catchLedge(rig)
      flutterGills(rig)
    }
    library.registerSignature(flutter, characterID: "pip", clip: flutterGills)
  }

  private static func breathe(_ rig: CharacterRig) {
    guard let axolotl = rig as? AxolotlRig else { return }
    CreatureMotion.blink(rig)
    RigAnimation.oscillate(axolotl.leftGills, leftRest)
    RigAnimation.oscillate(axolotl.rightGills, rightRest)
    RigAnimation.oscillate(axolotl.tail, swish)
  }

  private static func flutterGills(_ rig: CharacterRig) {
    guard let axolotl = rig as? AxolotlRig else { return }
    rig.delight.opacity = 1
    RigAnimation.oscillate(axolotl.leftGills, leftFlutter)
    RigAnimation.oscillate(axolotl.rightGills, rightFlutter)
    RigAnimation.oscillate(axolotl.tail, swish)
  }
}
