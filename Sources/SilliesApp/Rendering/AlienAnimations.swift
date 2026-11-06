import QuartzCore
import SilliesCore

@MainActor
enum AlienAnimations {
  static let scan: AnimationID = "novi.scan"
  static let float: AnimationID = "novi.float"
  private static let scanDuration = 3.4
  private static let floatDuration = 2.8

  static func register(in library: AnimationLibrary) {
    library.registerSecondaryMotion(characterID: "novi") { rig in
      guard let alien = rig as? AlienRig else { return }
      RigAnimation.swing(
        alien.leftAntenna, "transform.rotation.z", from: 0, to: -0.12, duration: 1.1)
      RigAnimation.swing(
        alien.rightAntenna, "transform.rotation.z", from: 0, to: 0.16, duration: 0.85)
    }
    library.register(.idle, characterID: "novi", clip: CreatureMotion.blink)
    library.register(.walk, characterID: "novi", clip: walk)
    library.register(.listen, characterID: "novi", clip: listen)
    library.register(.climb, characterID: "novi", clip: CreatureMotion.climb)
    library.register(.hangCatch, characterID: "novi", clip: CreatureMotion.catchLedge)
    library.registerSignature(scan, characterID: "novi", clip: inspect)
    library.registerSignature(float, characterID: "novi", clip: forgetGravity)
  }

  private static func walk(_ rig: CharacterRig) {
    CreatureMotion.steps(rig)
    CreatureMotion.blink(rig)
    RigAnimation.swing(rig.stage, "transform.translation.y", from: 0, to: 3, duration: 0.3)
    RigAnimation.swing(rig.leftArm, "transform.rotation.z", from: 0.16, to: -0.16, duration: 0.3)
    RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: -0.16, to: 0.16, duration: 0.3)
  }

  private static func listen(_ rig: CharacterRig) {
    CreatureMotion.blink(rig)
    RigAnimation.swing(rig.head, "transform.rotation.z", from: 0, to: -0.045, duration: 1.2)
  }

  private static func inspect(_ rig: CharacterRig) {
    guard let alien = rig as? AlienRig else { return }
    let beats: [NSNumber] = [0, 0.16, 0.4, 0.57, 0.82, 1]
    RigAnimation.play(
      alien.scanGlow,
      .init(
        keyPath: "opacity", values: [0, 0.8, 0.8, 0, 0, 0], times: beats, duration: scanDuration))
    RigAnimation.play(
      alien.notebook,
      .init(keyPath: "opacity", values: [0, 0, 0, 1, 1, 0], times: beats, duration: scanDuration))
    RigAnimation.play(
      alien.pencil,
      .init(keyPath: "opacity", values: [0, 0, 0, 1, 1, 0], times: beats, duration: scanDuration))
    RigAnimation.play(
      rig.head,
      .init(
        keyPath: "transform.rotation.z", values: [0, -0.13, 0.05, -0.08, -0.08, 0], times: beats,
        duration: scanDuration))
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0.9, 0.9, 1.5, 1.5, 0], times: beats,
        duration: scanDuration))
    RigAnimation.play(
      alien.pencil,
      .init(
        keyPath: "transform.translation.x", values: [0, 0, -2, 2, -2, 2, 0],
        times: [0, 0.55, 0.6, 0.65, 0.7, 0.75, 1], duration: scanDuration))
  }

  private static func forgetGravity(_ rig: CharacterRig) {
    let beats: [NSNumber] = [0, 0.15, 0.42, 0.68, 0.88, 1]
    RigAnimation.play(
      rig.stage,
      .init(
        keyPath: "transform.translation.y", values: [0, 0, 8, 8, 0, 0], times: beats,
        duration: floatDuration))
    RigAnimation.play(
      rig.stage,
      .init(
        keyPath: "transform.scale.y", values: [1, 0.96, 1.02, 1.02, 0.94, 1], times: beats,
        duration: floatDuration))
    RigAnimation.play(
      rig.leftFoot,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0, -0.25, -0.25, 0, 0], times: beats,
        duration: floatDuration))
    RigAnimation.play(
      rig.rightFoot,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0, 0.25, 0.25, 0, 0], times: beats,
        duration: floatDuration))
  }
}
