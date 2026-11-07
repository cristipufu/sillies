import QuartzCore
import SilliesCore

@MainActor
enum GoblinAnimations {
  static let tinker: AnimationID = "gizmo.tinker"
  static let mishap: AnimationID = "gizmo.mishap"
  private static let tinkerDuration = 3.6
  private static let mishapDuration = 2.6

  static func register(in library: AnimationLibrary) {
    CreatureMotion.registerBiped(characterID: "gizmo", in: library, walk: tiptoe)
    library.registerSecondaryMotion(characterID: "gizmo") { rig in
      guard let goblin = rig as? GoblinRig else { return }
      RigAnimation.swing(goblin.leftEar, "transform.rotation.z", from: 0, to: 0.06, duration: 1.1)
      RigAnimation.swing(goblin.rightEar, "transform.rotation.z", from: 0, to: -0.08, duration: 1.3)
    }
    library.registerSignature(tinker, characterID: "gizmo", clip: repair)
    library.registerSignature(mishap, characterID: "gizmo", clip: actInnocent)
  }

  private static func tiptoe(_ rig: CharacterRig) {
    CreatureMotion.waddle(rig)
    CreatureMotion.blink(rig)
    RigAnimation.swing(rig.head, "transform.rotation.z", from: 0, to: -0.06, duration: 0.6)
    RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: -0.15, to: -0.4, duration: 0.3)
  }

  private static func repair(_ rig: CharacterRig) {
    guard let goblin = rig as? GoblinRig else { return }
    let beats: [NSNumber] = [0, 0.14, 0.28, 0.4, 0.52, 0.64, 0.82, 1]
    RigAnimation.play(
      goblin.gadget,
      .init(
        keyPath: "opacity", values: [0, 1, 1, 1, 1, 1, 1, 0], times: beats, duration: tinkerDuration
      ))
    RigAnimation.play(
      goblin.goggles,
      .init(
        keyPath: "transform.translation.y", values: [0, -13, -13, -13, -13, -13, 0, 0],
        times: beats, duration: tinkerDuration))
    RigAnimation.play(
      rig.leftArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0.7, 0.7, 0.7, 0.7, 0.7, 0.3, 0], times: beats,
        duration: tinkerDuration))
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, -0.7, -0.85, -0.65, -0.85, -0.65, -0.3, 0],
        times: beats, duration: tinkerDuration))
    RigAnimation.play(
      goblin.gadgetNeedle,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0, -0.8, 0.5, -0.6, 0.7, 0, 0], times: beats,
        duration: tinkerDuration))
    RigAnimation.play(
      rig.head,
      .init(
        keyPath: "transform.rotation.z", values: [0, -0.06, -0.06, 0.06, -0.06, 0.06, -0.1, 0],
        times: beats, duration: tinkerDuration))
  }

  private static func actInnocent(_ rig: CharacterRig) {
    guard let goblin = rig as? GoblinRig else { return }
    let beats: [NSNumber] = [0, 0.16, 0.27, 0.45, 0.7, 1]
    RigAnimation.play(
      goblin.gadget,
      .init(keyPath: "opacity", values: [0, 1, 1, 1, 0, 0], times: beats, duration: mishapDuration))
    RigAnimation.play(
      goblin.steam,
      .init(
        keyPath: "opacity", values: [0, 0, 0.8, 0.5, 0, 0], times: beats, duration: mishapDuration))
    RigAnimation.play(
      goblin.steam,
      .init(
        keyPath: "transform.translation.y", values: [0, 0, 2, 8, 14, 0], times: beats,
        duration: mishapDuration))
    RigAnimation.play(
      rig.stage,
      .init(
        keyPath: "transform.translation.y", values: [0, 0, 4, 0, 0, 0], times: beats,
        duration: mishapDuration))
    RigAnimation.play(
      rig.head,
      .init(
        keyPath: "transform.rotation.z", values: [0, -0.05, 0.1, -0.1, 0.08, 0], times: beats,
        duration: mishapDuration))
    RigAnimation.play(
      rig.leftArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0.6, 0.6, 1.2, 0.8, 0], times: beats,
        duration: mishapDuration))
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, -0.6, -0.6, -1.2, -0.8, 0], times: beats,
        duration: mishapDuration))
  }
}
