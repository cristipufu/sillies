import QuartzCore
import SilliesCore

@MainActor
enum FrogAnimations {
  static let hop: AnimationID = "pogo.hop"
  static let pocket: AnimationID = "pogo.pocket"

  static func register(in library: AnimationLibrary) {
    library.register(.idle, characterID: "pogo") { rig in
      RigAnimation.keyframes(
        rig.eyes, "transform.scale.y", values: [1, 1, 0.08, 1, 1, 0.08, 1, 1],
        times: [0, 0.70, 0.73, 0.76, 0.80, 0.83, 0.86, 1], duration: 6)
    }
    library.register(.walk, characterID: "pogo", clip: waddle)
    library.register(.balance, characterID: "pogo", clip: wobble)
    library.register(.brace, characterID: "pogo") { rig in
      RigAnimation.swing(rig.torso, "transform.scale.x", from: 1, to: 1.12, duration: 0.25)
      RigAnimation.swing(rig.head, "transform.rotation.z", from: -0.08, to: 0.08, duration: 0.25)
      RigAnimation.swing(rig.leftArm, "transform.rotation.z", from: -0.6, to: -0.2, duration: 0.18)
      RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: 0.6, to: 0.2, duration: 0.18)
    }
    library.register(.hang, characterID: "pogo") { rig in
      RigAnimation.swing(rig.stage, "transform.rotation.z", from: -0.025, to: 0.025, duration: 1.2)
      RigAnimation.swing(rig.leftFoot, "transform.rotation.z", from: -0.3, to: 0.1, duration: 0.7)
      RigAnimation.swing(rig.rightFoot, "transform.rotation.z", from: 0.1, to: -0.3, duration: 0.9)
    }
    library.register(.climb, characterID: "pogo", clip: climb)
    library.register(.hangCatch, characterID: "pogo", clip: stickyCatch)
    library.register(hop, characterID: "pogo", clip: hopInPlace)
    library.registerReducedMotion(hop, characterID: "pogo") { rig in
      rig.eyes.opacity = 0
      rig.closedEyes.opacity = 1
      rig.delight.opacity = 1
    }
    library.register(pocket, characterID: "pogo") { rig in
      rig.delight.opacity = 1
      RigAnimation.keyframes(
        rig.accessory, "transform.scale", values: [1, 1.23, 0.96, 1], times: [0, 0.3, 0.65, 1],
        duration: 0.7, repeats: false)
      RigAnimation.keyframes(
        rig.head, "transform.rotation.z", values: [0, -0.10, 0], times: [0, 0.4, 1],
        duration: 0.9, repeats: false)
    }
    library.registerReducedMotion(pocket, characterID: "pogo") { rig in
      rig.delight.opacity = 1
    }
    for pose in [AttachmentPose.hangingLeft, .hangingRight] {
      library.registerVariant(hop, pose: pose, clip: .hangCatch)
    }
  }

  private static func waddle(_ rig: CharacterRig) {
    RigAnimation.swing(rig.leftFoot, "transform.rotation.z", from: -0.18, to: 0.18, duration: 0.3)
    RigAnimation.swing(rig.rightFoot, "transform.rotation.z", from: 0.18, to: -0.18, duration: 0.3)
    RigAnimation.swing(rig.torso, "transform.rotation.z", from: -0.04, to: 0.04, duration: 0.3)
    RigAnimation.swing(rig.stage, "transform.translation.y", from: 0, to: 2.5, duration: 0.3)
    RigAnimation.swing(rig.accessory, "transform.rotation.z", from: -0.10, to: 0.10, duration: 0.3)
  }

  private static func wobble(_ rig: CharacterRig) {
    RigAnimation.swing(rig.stage, "transform.rotation.z", from: -0.12, to: 0.12, duration: 0.22)
    RigAnimation.swing(rig.leftArm, "transform.rotation.z", from: -0.9, to: -0.4, duration: 0.15)
    RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: 0.9, to: 0.4, duration: 0.15)
    RigAnimation.swing(rig.accessory, "transform.rotation.z", from: -0.15, to: 0.15, duration: 0.22)
  }

  private static func climb(_ rig: CharacterRig) {
    // A brief pull, then a sticky pause. The upper hand remains at the contact anchor.
    RigAnimation.keyframes(
      rig.stage, "transform.translation.y", values: [0, -3, 3, 0, 0],
      times: [0, 0.12, 0.28, 0.45, 1], duration: 0.8)
    RigAnimation.keyframes(
      rig.secondaryGrip, "transform.translation.y", values: [0, 5, 5, 0, 0],
      times: [0, 0.15, 0.35, 0.5, 1], duration: 0.8)
    RigAnimation.swing(rig.leftFoot, "transform.rotation.z", from: -0.45, to: 0.2, duration: 0.4)
    RigAnimation.swing(rig.rightFoot, "transform.rotation.z", from: 0.2, to: -0.45, duration: 0.4)
  }

  private static func stickyCatch(_ rig: CharacterRig) {
    // Grips live outside stage: the body slips beneath fixed fingers, then recovers.
    RigAnimation.keyframes(
      rig.stage, "transform.translation.y", values: [0, -11, -11, 2, 0],
      times: [0, 0.18, 0.38, 0.75, 1], duration: 0.85, repeats: false)
    RigAnimation.keyframes(
      rig.torso, "transform.scale.y", values: [1, 1.15, 1.15, 0.94, 1],
      times: [0, 0.18, 0.38, 0.75, 1], duration: 0.85, repeats: false)
    RigAnimation.swing(rig.leftFoot, "transform.rotation.z", from: -0.5, to: 0.2, duration: 0.16)
    RigAnimation.swing(rig.rightFoot, "transform.rotation.z", from: 0.2, to: -0.5, duration: 0.16)
  }

  private static func hopInPlace(_ rig: CharacterRig) {
    rig.eyes.opacity = 0
    rig.closedEyes.opacity = 1
    RigAnimation.keyframes(
      rig.stage, "transform.scale.y", values: [1, 0.8, 1.1, 1, 0.9, 1],
      times: [0, 0.15, 0.3, 0.65, 0.8, 1], duration: 0.8, repeats: false)
    RigAnimation.keyframes(
      rig.stage, "transform.translation.y", values: [0, 0, 12, 0, 0],
      times: [0, 0.2, 0.45, 0.8, 1], duration: 0.8, repeats: false)
    RigAnimation.keyframes(
      rig.accessory, "transform.rotation.z", values: [0, -0.18, 0.10, 0],
      times: [0, 0.35, 0.7, 1], duration: 0.9, repeats: false)
  }
}
