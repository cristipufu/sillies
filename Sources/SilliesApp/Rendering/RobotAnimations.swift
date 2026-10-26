import QuartzCore
import SilliesCore

@MainActor
enum RobotAnimations {
  static let scan: AnimationID = "bolt.scan"

  static func register(in library: AnimationLibrary) {
    library.register(.idle, characterID: "bolt") { rig in
      RigAnimation.keyframes(
        rig.eyes, "transform.scale.y", values: [1, 1, 0.16, 1, 1],
        times: [0, 0.84, 0.87, 0.9, 1], duration: 4.8)
    }
    library.register(.walk, characterID: "bolt", clip: march)
    library.register(.brace, characterID: "bolt", clip: recalibrate)
    library.register(.balance, characterID: "bolt", clip: march)
    library.register(.peek, characterID: "bolt") { rig in
      RigAnimation.keyframes(
        rig.head, "transform.rotation.z", values: [0, -0.10, -0.10, 0.06, 0],
        times: [0, 0.2, 0.5, 0.75, 1], duration: 1.8, repeats: false)
    }
    library.register(.listen, characterID: "bolt") { rig in
      guard let robot = rig as? RobotRig else { return }
      RigAnimation.swing(robot.antenna, "transform.rotation.z", from: -0.2, to: 0.2, duration: 0.3)
      RigAnimation.swing(robot.head, "transform.rotation.z", from: -0.04, to: 0.04, duration: 0.6)
    }
    library.register(.hang, characterID: "bolt") { rig in
      guard let robot = rig as? RobotRig else { return }
      RigAnimation.swing(robot.antenna, "transform.rotation.z", from: -0.08, to: 0.08, duration: 1)
      RigAnimation.swing(robot.leftFoot, "transform.rotation.z", from: -0.06, to: 0.06, duration: 1)
      RigAnimation.swing(
        robot.rightFoot, "transform.rotation.z", from: 0.06, to: -0.06, duration: 1)
    }
    library.register(.climb, characterID: "bolt", clip: climb)
    library.register(.hangCatch, characterID: "bolt", clip: magneticCatch)
    library.register(scan, characterID: "bolt") { rig in
      guard let robot = rig as? RobotRig else { return }
      showViewfinder(robot)
      RigAnimation.keyframes(
        robot.viewfinder, "opacity", values: [0, 1, 1, 0.4, 1],
        times: [0, 0.15, 0.55, 0.65, 1], duration: 0.65, repeats: false)
      RigAnimation.keyframes(
        robot.head, "transform.rotation.z", values: [0, -0.035, 0], times: [0, 0.3, 1],
        duration: 0.65, repeats: false)
    }
    library.registerReducedMotion(scan, characterID: "bolt") { rig in
      guard let robot = rig as? RobotRig else { return }
      showViewfinder(robot)
    }
  }

  private static func march(_ rig: CharacterRig) {
    for (foot, direction) in [(rig.leftFoot, 1.0), (rig.rightFoot, -1.0)] {
      RigAnimation.keyframes(
        foot, "transform.rotation.z", values: [0, 0.16 * direction, 0, -0.16 * direction, 0],
        times: [0, 0.2, 0.5, 0.7, 1], duration: 0.7)
    }
    RigAnimation.swing(rig.leftArm, "transform.rotation.z", from: 0.1, to: -0.1, duration: 0.35)
    RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: -0.1, to: 0.1, duration: 0.35)
    RigAnimation.keyframes(
      rig.stage, "transform.translation.y", values: [0, 1.2, 0, 1.2, 0],
      times: [0, 0.2, 0.5, 0.7, 1], duration: 0.7)
  }

  private static func recalibrate(_ rig: CharacterRig) {
    for (foot, direction) in [(rig.leftFoot, -1.0), (rig.rightFoot, 1.0)] {
      RigAnimation.keyframes(
        foot, "transform.scale.y", values: [1, 1.45, 0.88, 1.15, 1],
        times: [0, 0.2, 0.45, 0.7, 1], duration: 0.8)
      RigAnimation.keyframes(
        foot, "transform.translation.x", values: [0, direction * 3, 0, direction, 0],
        times: [0, 0.2, 0.45, 0.7, 1], duration: 0.8)
    }
    RigAnimation.swing(rig.head, "transform.rotation.z", from: -0.055, to: 0.055, duration: 0.4)
  }

  private static func climb(_ rig: CharacterRig) {
    RigAnimation.keyframes(
      rig.secondaryGrip, "transform.translation.y", values: [0, 6, 6, 0, 0],
      times: [0, 0.15, 0.4, 0.6, 1], duration: 0.7)
    RigAnimation.keyframes(
      rig.stage, "transform.translation.y", values: [0, 0, 3, 3, 0],
      times: [0, 0.2, 0.4, 0.65, 1], duration: 0.7)
    RigAnimation.swing(rig.leftFoot, "transform.rotation.z", from: -0.2, to: 0.1, duration: 0.35)
    RigAnimation.swing(rig.rightFoot, "transform.rotation.z", from: 0.1, to: -0.2, duration: 0.35)
  }

  private static func magneticCatch(_ rig: CharacterRig) {
    RigAnimation.keyframes(
      rig.stage, "transform.translation.y", values: [0, -4, 1, 0], times: [0, 0.2, 0.65, 1],
      duration: 0.5, repeats: false)
    recalibrate(rig)
  }

  private static func showViewfinder(_ rig: RobotRig) {
    rig.eyes.opacity = 0
    rig.closedEyes.opacity = 0
    rig.viewfinder.opacity = 1
  }
}
