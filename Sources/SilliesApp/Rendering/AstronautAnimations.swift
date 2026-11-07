import QuartzCore
import SilliesCore

@MainActor
enum AstronautAnimations {
  static let check: AnimationID = "orbit.check"
  static let moonstep: AnimationID = "orbit.moonstep"
  private static let checkDuration = 3.0
  private static let moonstepDuration = 3.4

  static func register(in library: AnimationLibrary) {
    CreatureMotion.registerBiped(characterID: "orbit", in: library, walk: moonWalk)
    library.registerSecondaryMotion(characterID: "orbit") { rig in
      guard let astronaut = rig as? AstronautRig else { return }
      RigAnimation.swing(astronaut.visorShine, "opacity", from: 0.65, to: 1, duration: 1.8)
    }
    library.registerSignature(check, characterID: "orbit", clip: checkWrist)
    library.registerSignature(moonstep, characterID: "orbit", clip: littleLeap)
  }

  private static func moonWalk(_ rig: CharacterRig) {
    CreatureMotion.blink(rig)
    RigAnimation.swing(rig.leftFoot, "transform.rotation.z", from: -0.18, to: 0.18, duration: 0.5)
    RigAnimation.swing(rig.rightFoot, "transform.rotation.z", from: 0.18, to: -0.18, duration: 0.5)
    RigAnimation.swing(rig.stage, "transform.translation.y", from: 0, to: 3, duration: 0.5)
    RigAnimation.swing(rig.leftArm, "transform.rotation.z", from: 0, to: 0.18, duration: 0.5)
    RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: 0, to: -0.18, duration: 0.5)
  }

  private static func checkWrist(_ rig: CharacterRig) {
    guard let astronaut = rig as? AstronautRig else { return }
    let beats: [NSNumber] = [0, 0.18, 0.34, 0.5, 0.68, 0.84, 1]
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, -1.2, -1.2, -1.2, -1.2, -0.5, 0], times: beats,
        duration: checkDuration))
    RigAnimation.play(
      rig.head,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0.12, 0.12, 0.07, 0.12, -0.04, 0],
        times: beats, duration: checkDuration))
    RigAnimation.play(
      astronaut.wristDisplay,
      .init(
        keyPath: "opacity", values: [1, 1, 0.3, 1, 0.3, 1, 1], times: beats, duration: checkDuration
      ))
    RigAnimation.play(
      rig.leftArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0, 0.5, 0.7, 0.5, 0, 0], times: beats,
        duration: checkDuration))
  }

  private static func littleLeap(_ rig: CharacterRig) {
    guard let astronaut = rig as? AstronautRig else { return }
    let beats: [NSNumber] = [0, 0.15, 0.3, 0.52, 0.72, 0.88, 1]
    RigAnimation.play(
      rig.stage,
      .init(
        keyPath: "transform.translation.y", values: [0, -2, 7, 8, 4, -1, 0], times: beats,
        duration: moonstepDuration))
    RigAnimation.play(
      rig.stage,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0, -0.06, 0.06, -0.02, 0, 0], times: beats,
        duration: moonstepDuration))
    RigAnimation.play(
      rig.leftArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0.15, 0.9, 1.1, 0.7, 0.15, 0], times: beats,
        duration: moonstepDuration))
    RigAnimation.play(
      rig.rightArm,
      .init(
        keyPath: "transform.rotation.z", values: [0, -0.15, -0.9, -1.1, -0.7, -0.15, 0],
        times: beats, duration: moonstepDuration))
    RigAnimation.play(
      astronaut.thrusters,
      .init(
        keyPath: "opacity", values: [0, 0, 0.8, 0.4, 0, 0, 0], times: beats,
        duration: moonstepDuration))
    RigAnimation.play(
      rig.leftFoot,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0, -0.2, -0.3, -0.15, 0, 0], times: beats,
        duration: moonstepDuration))
    RigAnimation.play(
      rig.rightFoot,
      .init(
        keyPath: "transform.rotation.z", values: [0, 0, 0.2, 0.3, 0.15, 0, 0], times: beats,
        duration: moonstepDuration))
  }
}
