import QuartzCore
import SilliesCore

@MainActor
enum MimeAnimations {
  static let glass: AnimationID = "mimo.glass"
  static let bow: AnimationID = "mimo.bow"
  private static let glassDuration = 3.6
  private static let bowDuration = 2.8

  static func register(in library: AnimationLibrary) {
    CreatureMotion.registerBiped(characterID: "mimo", in: library, walk: tiptoe)
    library.registerSecondaryMotion(characterID: "mimo") { rig in
      guard let mime = rig as? MimeRig else { return }
      RigAnimation.swing(mime.scarf, "transform.rotation.z", from: 0, to: 0.08, duration: 1.2)
      RigAnimation.swing(mime.beret, "transform.rotation.z", from: 0, to: -0.025, duration: 1.4)
    }
    library.registerSignature(glass, characterID: "mimo", clip: invisibleGlass)
    library.registerSignature(bow, characterID: "mimo", clip: curtainCall)
  }

  private static func tiptoe(_ rig: CharacterRig) {
    CreatureMotion.waddle(rig)
    CreatureMotion.blink(rig)
    RigAnimation.swing(rig.head, "transform.translation.y", from: 0, to: 1.3, duration: 0.6)
    RigAnimation.swing(rig.leftArm, "transform.rotation.z", from: 0, to: 0.3, duration: 0.3)
    RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: 0.3, to: 0, duration: 0.3)
  }

  private static func invisibleGlass(_ rig: CharacterRig) {
    guard let mime = rig as? MimeRig else { return }
    let beats: [NSNumber] = [0, 0.14, 0.3, 0.46, 0.62, 0.82, 1]
    for arm in [rig.leftArm, rig.rightArm] {
      RigAnimation.play(
        arm,
        .init(
          keyPath: "opacity", values: [1, 0, 0, 0, 0, 0, 1], times: beats, duration: glassDuration))
    }
    RigAnimation.play(
      mime.reachingHands,
      .init(
        keyPath: "opacity", values: [0, 1, 1, 1, 1, 1, 0], times: beats, duration: glassDuration))
    RigAnimation.play(
      mime.reachingHands,
      .init(
        keyPath: "transform.translation.y", values: [0, 0, 1, -1, 1, 0, 0], times: beats,
        duration: glassDuration))
    RigAnimation.play(
      mime.contactMarks,
      .init(
        keyPath: "opacity", values: [0, 0, 0.8, 0, 0.7, 0, 0], times: beats, duration: glassDuration
      ))
    RigAnimation.play(
      rig.head,
      .init(
        keyPath: "transform.rotation.z", values: [0, -0.07, 0.07, 0.07, -0.07, -0.07, 0],
        times: beats, duration: glassDuration))
    RigAnimation.play(
      rig.torso,
      .init(
        keyPath: "transform.translation.x", values: [0, -1, -2, 2, 1, 0, 0], times: beats,
        duration: glassDuration))
  }

  private static func curtainCall(_ rig: CharacterRig) {
    guard let mime = rig as? MimeRig else { return }
    let beats: [NSNumber] = [0, 0.18, 0.36, 0.6, 0.8, 1]
    RigAnimation.play(
      rig.stage,
      .init(
        keyPath: "transform.scale.y", values: [1, 1.02, 0.9, 0.9, 1.02, 1], times: beats,
        duration: bowDuration))
    RigAnimation.play(
      rig.head,
      .init(
        keyPath: "transform.translation.y", values: [0, 1, -6, -6, 0, 0], times: beats,
        duration: bowDuration))
    RigAnimation.play(
      rig.leftArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, 1, 0.6, 0.6, 0.2, 0], times: beats,
        duration: bowDuration))
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, -1, -0.6, -0.6, -0.2, 0], times: beats,
        duration: bowDuration))
    RigAnimation.play(
      mime.beret,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0, -0.12, -0.12, 0.04, 0], times: beats,
        duration: bowDuration))
  }
}
