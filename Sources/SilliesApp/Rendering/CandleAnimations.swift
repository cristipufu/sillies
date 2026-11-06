import QuartzCore
import SilliesCore

@MainActor
enum CandleAnimations {
  static let warmHands: AnimationID = "flick.warmHands"
  static let glow: AnimationID = "flick.glow"
  private static let warmingDuration = 3.2

  static func register(in library: AnimationLibrary) {
    library.registerSecondaryMotion(characterID: "flick", clip: flicker)
    library.register(.idle, characterID: "flick", clip: CreatureMotion.blink)
    library.register(.walk, characterID: "flick", clip: walk)
    library.register(.listen, characterID: "flick", clip: listen)
    library.register(.sleep, characterID: "flick", clip: sleep)
    library.register(.climb, characterID: "flick", clip: CreatureMotion.climb)
    library.register(.hangCatch, characterID: "flick", clip: CreatureMotion.catchLedge)
    library.registerSignature(warmHands, characterID: "flick", clip: warm)
    library.registerSignature(glow, characterID: "flick", clip: brighten)
  }

  private static func flicker(_ rig: CharacterRig) {
    guard let candle = rig as? CandleRig else { return }
    // Different periods keep the flame and its warm core from moving as one rigid cutout.
    RigAnimation.loop(
      candle.flame,
      .init(
        keyPath: "transform.rotation.z", values: [0, -0.08, 0.045, -0.025, 0],
        times: [0, 0.27, 0.55, 0.78, 1], duration: 1.7))
    RigAnimation.loop(
      candle.flame,
      .init(
        keyPath: "transform.scale.y", values: [1, 1.07, 0.97, 1.04, 1],
        times: [0, 0.23, 0.49, 0.76, 1], duration: 1.3))
    RigAnimation.swing(candle.flameCore, "transform.scale.x", from: 1, to: 0.85, duration: 0.6)
    RigAnimation.swing(candle.glow, "opacity", from: 1, to: 0.7, duration: 1.4)
  }

  private static func walk(_ rig: CharacterRig) {
    guard let candle = rig as? CandleRig else { return }
    CreatureMotion.steps(rig)
    CreatureMotion.blink(rig)
    RigAnimation.swing(rig.stage, "transform.scale.y", from: 1, to: 0.96, duration: 0.32)
    RigAnimation.swing(candle.flame, "transform.rotation.z", from: 0.08, to: 0.2, duration: 0.64)
  }

  private static func listen(_ rig: CharacterRig) {
    guard let candle = rig as? CandleRig else { return }
    CreatureMotion.blink(rig)
    RigAnimation.swing(candle.flame, "transform.scale.y", from: 1.06, to: 1.15, duration: 0.9)
  }

  private static func sleep(_ rig: CharacterRig) {
    guard let candle = rig as? CandleRig else { return }
    rig.eyes.opacity = 0
    rig.closedEyes.opacity = 1
    rig.sleepMark.opacity = 1
    RigAnimation.swing(candle.flame, "transform.scale.y", from: 0.78, to: 0.85, duration: 2.2)
  }

  private static func warm(_ rig: CharacterRig) {
    let beats: [NSNumber] = [0, 0.2, 0.5, 0.68, 0.83, 1]
    RigAnimation.play(
      rig.leftArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, 2.65, 2.65, 2.65, 1.8, 0], times: beats,
        duration: warmingDuration))
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, -2.65, -2.65, -2.65, -1.8, 0], times: beats,
        duration: warmingDuration))
    RigAnimation.play(
      rig.eyes,
      .init(
        keyPath: "transform.translation.x", values: [0, 0, 0, -2, 1, 0], times: beats,
        duration: warmingDuration))
    for arm in [rig.leftArm, rig.rightArm] {
      RigAnimation.play(
        arm,
        .init(
          keyPath: "transform.scale.y", values: [1, 1.4, 1.4, 1.4, 1.1, 1],
          times: beats, duration: warmingDuration))
    }
    RigAnimation.play(
      rig.closedEyes,
      .init(
        keyPath: "opacity", values: [0, 1, 1, 0, 0, 0], times: beats, duration: warmingDuration))
    RigAnimation.play(
      rig.eyes,
      .init(
        keyPath: "opacity", values: [1, 0, 0, 1, 1, 1], times: beats, duration: warmingDuration))
  }

  private static func brighten(_ rig: CharacterRig) {
    guard let candle = rig as? CandleRig else { return }
    RigAnimation.play(
      candle.flame,
      .init(
        keyPath: "transform.scale", values: [1, 0.92, 1.18, 1], times: [0, 0.2, 0.55, 1],
        duration: 1.8))
    RigAnimation.play(
      candle.glow,
      .init(keyPath: "transform.scale", values: [1, 1.25, 1], times: [0, 0.55, 1], duration: 1.8))
  }
}
