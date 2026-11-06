import QuartzCore
import SilliesCore

@MainActor
enum WitchAnimations {
  static let conjure: AnimationID = "lumi.conjure"
  static let catchHat: AnimationID = "lumi.catchHat"
  private static let spellDuration = 3.2
  private static let landingDuration = 0.9

  static func register(in library: AnimationLibrary) {
    library.registerSecondaryMotion(characterID: "lumi", clip: swayCharm)
    library.register(.idle, characterID: "lumi", clip: CreatureMotion.blink)
    library.register(.walk, characterID: "lumi", clip: walk)
    library.register(.listen, characterID: "lumi") { rig in
      CreatureMotion.blink(rig)
      RigAnimation.swing(rig.head, "transform.rotation.z", from: 0, to: 0.04, duration: 1.3)
    }
    library.register(.land, characterID: "lumi", clip: settleHat)
    library.register(.climb, characterID: "lumi", clip: CreatureMotion.climb)
    library.register(.hangCatch, characterID: "lumi", clip: CreatureMotion.catchLedge)
    library.registerSignature(conjure, characterID: "lumi", clip: conjureStar)
    library.registerSignature(catchHat, characterID: "lumi", clip: settleHat)
  }

  private static func swayCharm(_ rig: CharacterRig) {
    guard let witch = rig as? WitchRig else { return }
    RigAnimation.swing(witch.hatCharm, "transform.rotation.z", from: 0, to: 0.18, duration: 1.1)
  }

  private static func walk(_ rig: CharacterRig) {
    guard let witch = rig as? WitchRig else { return }
    CreatureMotion.steps(rig)
    CreatureMotion.blink(rig)
    RigAnimation.swing(rig.stage, "transform.translation.y", from: 0, to: 2.5, duration: 0.3)
    RigAnimation.swing(witch.hat, "transform.rotation.z", from: -0.035, to: 0.05, duration: 0.6)
    RigAnimation.swing(
      witch.hatCharm, "transform.rotation.z", from: 0.22, to: -0.22, duration: 0.65)
  }

  private static func settleHat(_ rig: CharacterRig) {
    guard let witch = rig as? WitchRig else { return }
    let beats: [NSNumber] = [0, 0.18, 0.42, 0.7, 1]
    RigAnimation.play(
      rig.stage,
      .init(
        keyPath: "transform.scale.y", values: [1, 0.88, 1.04, 0.99, 1], times: beats,
        duration: landingDuration))
    RigAnimation.play(
      witch.hat,
      .init(
        keyPath: "transform.rotation.z", values: [0, -0.12, 0.08, -0.03, 0], times: beats,
        duration: landingDuration))
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, -2.8, -3, -2.8, 0], times: beats,
        duration: landingDuration))
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "transform.scale.y", values: [1, 1.35, 1.35, 1.2, 1], times: beats,
        duration: landingDuration))
  }

  private static func conjureStar(_ rig: CharacterRig) {
    guard let witch = rig as? WitchRig else { return }
    let beats: [NSNumber] = [0, 0.15, 0.35, 0.52, 0.69, 0.84, 1]
    RigAnimation.play(
      witch.spellStar,
      .init(
        keyPath: "opacity", values: [0, 1, 1, 1, 1, 0, 0], times: beats, duration: spellDuration))
    RigAnimation.play(
      witch.spellStar,
      .init(
        keyPath: "transform.translation.x", values: [0, 0, 8, -12, -34, -38, -38], times: beats,
        duration: spellDuration))
    RigAnimation.play(
      witch.spellStar,
      .init(
        keyPath: "transform.translation.y", values: [0, 3, 16, 29, 30, 22, 22], times: beats,
        duration: spellDuration))
    RigAnimation.play(
      witch.spellStar,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0.2, -0.2, 0.5, 1.2, 1.4, 1.4], times: beats,
        duration: spellDuration))
    RigAnimation.play(
      witch.hat,
      .init(
        keyPath: "transform.translation.y", values: [0, 0, 0, 0, 7, 0, 0], times: beats,
        duration: spellDuration))
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, 2.8, 2.7, 2.9, 3.28, 3.28, 0], times: beats,
        duration: spellDuration))
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "transform.scale.y", values: [1, 1, 1, 1, 1.4, 1.4, 1], times: beats,
        duration: spellDuration))
    RigAnimation.play(
      rig.head,
      .init(
        keyPath: "transform.rotation.z", values: [0, -0.08, -0.13, 0.09, 0.04, 0, 0], times: beats,
        duration: spellDuration))
  }
}
