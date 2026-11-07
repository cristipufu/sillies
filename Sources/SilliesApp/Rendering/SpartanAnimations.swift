import QuartzCore
import SilliesCore

@MainActor
enum SpartanAnimations {
  static let training: AnimationID = "leon.training"
  static let victory: AnimationID = "leon.victory"
  private static let trainingDuration = 3.2
  private static let victoryDuration = 2.4

  static func register(in library: AnimationLibrary) {
    CreatureMotion.registerBiped(characterID: "leon", in: library, walk: march)
    library.registerSecondaryMotion(characterID: "leon") { rig in
      guard let spartan = rig as? SpartanRig else { return }
      RigAnimation.swing(
        spartan.crest, "transform.rotation.z", from: -0.04, to: 0.06, duration: 0.8)
    }
    library.registerSignature(training, characterID: "leon", clip: warmUp)
    library.registerSignature(victory, characterID: "leon", clip: celebrate)
  }

  private static func march(_ rig: CharacterRig) {
    CreatureMotion.steps(rig)
    CreatureMotion.blink(rig)
    RigAnimation.swing(rig.stage, "transform.translation.y", from: 0, to: 2, duration: 0.26)
    RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: -0.25, to: 0.25, duration: 0.26)
  }

  private static func warmUp(_ rig: CharacterRig) {
    guard let spartan = rig as? SpartanRig else { return }
    let beats: [NSNumber] = [0, 0.12, 0.28, 0.4, 0.56, 0.7, 0.87, 1]
    RigAnimation.play(
      rig.stage,
      .init(
        keyPath: "transform.translation.y", values: [0, -3, 1, -3, 1, -3, 2, 0], times: beats,
        duration: trainingDuration))
    RigAnimation.play(
      rig.stage,
      .init(
        keyPath: "transform.scale.y", values: [1, 0.96, 1.02, 0.96, 1.02, 0.96, 1.02, 1],
        times: beats, duration: trainingDuration))
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, -0.4, -1.6, -0.4, -1.6, -0.4, -2.4, 0],
        times: beats, duration: trainingDuration))
    RigAnimation.play(
      spartan.shield,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0.1, -0.1, 0.1, -0.1, 0.1, 0, 0], times: beats,
        duration: trainingDuration))
    RigAnimation.play(
      spartan.crest,
      .init(
        keyPath: "transform.rotation.z", values: [0, -0.15, 0.12, -0.15, 0.12, -0.15, 0.08, 0],
        times: beats, duration: trainingDuration))
  }

  private static func celebrate(_ rig: CharacterRig) {
    guard let spartan = rig as? SpartanRig else { return }
    let beats: [NSNumber] = [0, 0.15, 0.32, 0.65, 0.84, 1]
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, -0.3, -2.7, -2.7, -2.4, 0], times: beats,
        duration: victoryDuration))
    RigAnimation.play(
      rig.leftArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0.2, 1.4, 1.4, 0.8, 0], times: beats,
        duration: victoryDuration))
    RigAnimation.play(
      rig.stage,
      .init(
        keyPath: "transform.translation.y", values: [0, -2, 5, 3, 0, 0], times: beats,
        duration: victoryDuration))
    RigAnimation.play(
      rig.head,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0, -0.08, -0.08, 0.03, 0], times: beats,
        duration: victoryDuration))
    RigAnimation.play(
      spartan.medalShine,
      .init(
        keyPath: "opacity", values: [0, 0, 0.8, 1, 0, 0], times: beats, duration: victoryDuration))
  }
}
