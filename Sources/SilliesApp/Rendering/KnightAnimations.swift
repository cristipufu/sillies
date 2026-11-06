import QuartzCore
import SilliesCore

@MainActor
enum KnightAnimations {
  static let polish: AnimationID = "rook.polish"
  static let visorSlip: AnimationID = "rook.visorSlip"
  private static let polishDuration = 3.4
  private static let visorDuration = 1.8

  static func register(in library: AnimationLibrary) {
    library.registerSecondaryMotion(characterID: "rook") { rig in
      guard let knight = rig as? KnightRig else { return }
      RigAnimation.swing(knight.cape, "transform.rotation.z", from: 0, to: 0.045, duration: 1.5)
    }
    library.register(.idle, characterID: "rook", clip: CreatureMotion.blink)
    library.register(.walk, characterID: "rook", clip: march)
    library.register(.listen, characterID: "rook") { rig in
      CreatureMotion.blink(rig)
      RigAnimation.swing(rig.head, "transform.rotation.z", from: 0, to: -0.035, duration: 1.5)
    }
    library.register(.climb, characterID: "rook", clip: CreatureMotion.climb)
    library.register(.hangCatch, characterID: "rook", clip: CreatureMotion.catchLedge)
    library.registerSignature(polish, characterID: "rook", clip: polishShield)
    library.registerSignature(visorSlip, characterID: "rook", clip: adjustVisor)
  }

  private static func march(_ rig: CharacterRig) {
    guard let knight = rig as? KnightRig else { return }
    CreatureMotion.steps(rig)
    CreatureMotion.blink(rig)
    RigAnimation.swing(rig.stage, "transform.translation.y", from: 0, to: 1.5, duration: 0.34)
    RigAnimation.swing(rig.head, "transform.rotation.z", from: -0.025, to: 0.025, duration: 0.34)
    RigAnimation.swing(knight.cape, "transform.rotation.z", from: 0.04, to: -0.09, duration: 0.68)
  }

  private static func polishShield(_ rig: CharacterRig) {
    guard let knight = rig as? KnightRig else { return }
    let beats: [NSNumber] = [0, 0.12, 0.24, 0.36, 0.48, 0.62, 0.8, 1]
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "opacity", values: [1, 0, 0, 0, 0, 1, 1, 1], times: beats, duration: polishDuration
      ))
    RigAnimation.play(
      knight.polishingArm,
      .init(
        keyPath: "opacity", values: [0, 1, 1, 1, 1, 0, 0, 0], times: beats, duration: polishDuration
      ))
    RigAnimation.play(
      knight.polishingArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0, -0.06, 0.04, -0.06, 0, 0, 0], times: beats,
        duration: polishDuration))
    RigAnimation.play(
      knight.shieldShine,
      .init(
        keyPath: "opacity", values: [0, 0, 0, 0, 0, 1, 0.2, 0], times: beats,
        duration: polishDuration))
    RigAnimation.play(
      rig.head,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0.1, 0.1, 0.1, 0.1, 0.08, -0.07, 0],
        times: beats, duration: polishDuration))
    RigAnimation.play(
      knight.cape,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0, 0, 0, 0, -0.12, 0.04, 0], times: beats,
        duration: polishDuration))
  }

  private static func adjustVisor(_ rig: CharacterRig) {
    guard let knight = rig as? KnightRig else { return }
    let beats: [NSNumber] = [0, 0.2, 0.38, 0.6, 0.8, 1]
    RigAnimation.play(
      knight.visor,
      .init(
        keyPath: "transform.translation.y", values: [0, -14, -14, -14, 2, 0], times: beats,
        duration: visorDuration))
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0, 0, -2.8, -2.8, 0], times: beats,
        duration: visorDuration))
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "transform.scale.y", values: [1, 1, 1, 1.15, 1.15, 1], times: beats,
        duration: visorDuration))
    RigAnimation.play(
      rig.head,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0.05, -0.05, 0, 0, 0], times: beats,
        duration: visorDuration))
  }
}
