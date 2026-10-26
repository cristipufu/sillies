import QuartzCore
import SilliesCore

/// Shared body clips. Character-specific overrides can be registered at composition time.
@MainActor
enum BuiltinAnimations {
  static func register(in library: AnimationLibrary) {
    library.register(.idle) { rig in
      RigAnimation.keyframes(
        rig.eyes, "transform.scale.y", values: [1, 1, 0.08, 1, 1], times: [0, 0.90, 0.93, 0.96, 1],
        duration: 5.5)
    }
    library.register(.walk) { rig in
      RigAnimation.swing(
        rig.leftFoot, "transform.rotation.z", from: -0.30, to: 0.30, duration: 0.23)
      RigAnimation.swing(
        rig.rightFoot, "transform.rotation.z", from: 0.30, to: -0.30, duration: 0.23)
      RigAnimation.swing(rig.leftArm, "transform.rotation.z", from: 0.13, to: -0.13, duration: 0.23)
      RigAnimation.swing(
        rig.rightArm, "transform.rotation.z", from: -0.13, to: 0.13, duration: 0.23)
      RigAnimation.swing(rig.stage, "transform.translation.y", from: 0, to: 2, duration: 0.23)
      RigAnimation.swing(
        rig.accessory, "transform.rotation.z", from: -0.025, to: 0.025, duration: 0.46)
    }
    library.register(.sleep) { rig in
      rig.eyes.opacity = 0
      rig.closedEyes.opacity = 1
      rig.sleepMark.opacity = 1
    }
    library.registerReducedMotion(.sleep) { rig in
      rig.eyes.opacity = 0
      rig.closedEyes.opacity = 1
      rig.sleepMark.opacity = 1
    }
    library.register(.surprised) { rig in
      RigAnimation.keyframes(
        rig.stage, "transform.scale.y", values: [1, 0.88, 1.13, 1], times: [0, 0.18, 0.5, 1],
        duration: 0.6, repeats: false)
      RigAnimation.keyframes(
        rig.stage, "transform.scale.x", values: [1, 1.1, 0.94, 1], times: [0, 0.18, 0.5, 1],
        duration: 0.6, repeats: false)
    }
    library.register(.balance) { rig in
      RigAnimation.swing(rig.stage, "transform.rotation.z", from: -0.08, to: 0.08, duration: 0.17)
      RigAnimation.swing(rig.leftArm, "transform.rotation.z", from: -0.6, to: -0.3, duration: 0.17)
      RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: 0.6, to: 0.3, duration: 0.17)
    }
    library.register(.wave) { rig in
      RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: 1.6, to: 2.4, duration: 0.18)
      RigAnimation.swing(rig.head, "transform.rotation.z", from: 0, to: 0.045, duration: 0.6)
    }
    library.register(.happy) { rig in
      rig.eyes.opacity = 0
      rig.closedEyes.opacity = 1
      rig.delight.opacity = 1
      RigAnimation.swing(rig.stage, "transform.translation.y", from: 0, to: 3, duration: 0.22)
      RigAnimation.swing(rig.delight, "opacity", from: 0.2, to: 1, duration: 0.45)
    }
    library.registerReducedMotion(.happy) { rig in
      rig.delight.opacity = 1
    }
    library.register(.tumble) { rig in
      RigAnimation.keyframes(
        rig.stage, "transform.rotation.z", values: [0, -0.20, 0.20, 0], times: [0, 0.25, 0.65, 1],
        duration: 0.7, repeats: false)
    }
    library.register(.peek) { rig in
      RigAnimation.swing(rig.head, "transform.rotation.z", from: -0.07, to: 0.10, duration: 0.8)
    }
    library.register(.meditate) { rig in
      rig.eyes.opacity = 0
      rig.closedEyes.opacity = 1
      RigAnimation.swing(rig.stage, "transform.translation.y", from: 0, to: 4, duration: 1.8)
    }
    library.registerReducedMotion(.meditate) { rig in
      rig.eyes.opacity = 0
      rig.closedEyes.opacity = 1
    }
    library.register(.brace) { rig in
      RigAnimation.keyframes(
        rig.stage, "transform.scale.y", values: [1, 0.78, 0.9, 0.85], times: [0, 0.18, 0.5, 1],
        duration: 0.35, repeats: false)
      RigAnimation.swing(rig.leftArm, "transform.rotation.z", from: -0.8, to: -0.45, duration: 0.12)
      RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: 0.8, to: 0.45, duration: 0.12)
      RigAnimation.swing(rig.head, "transform.rotation.z", from: -0.07, to: 0.07, duration: 0.14)
    }
    library.register(.scramble) { rig in
      RigAnimation.swing(rig.leftFoot, "transform.rotation.z", from: -0.7, to: 0.7, duration: 0.09)
      RigAnimation.swing(rig.rightFoot, "transform.rotation.z", from: 0.7, to: -0.7, duration: 0.09)
      RigAnimation.swing(rig.leftArm, "transform.rotation.z", from: -0.9, to: -0.2, duration: 0.13)
      RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: 0.9, to: 0.2, duration: 0.13)
      RigAnimation.swing(rig.stage, "transform.rotation.z", from: -0.10, to: 0.10, duration: 0.13)
    }
    library.register(.land) { rig in
      RigAnimation.keyframes(
        rig.stage, "transform.scale.y", values: [1, 0.68, 1.13, 0.96, 1],
        times: [0, 0.15, 0.42, 0.7, 1], duration: 0.55, repeats: false)
      RigAnimation.keyframes(
        rig.stage, "transform.scale.x", values: [1, 1.18, 0.94, 1.03, 1],
        times: [0, 0.15, 0.42, 0.7, 1], duration: 0.55, repeats: false)
      RigAnimation.keyframes(
        rig.dust, "opacity", values: [0, 0.7, 0], times: [0, 0.16, 1], duration: 0.5, repeats: false
      )
      RigAnimation.keyframes(
        rig.dust, "transform.scale", values: [0.7, 1.4], times: [0, 1], duration: 0.5,
        repeats: false)
    }
    library.register(.appear) { rig in
      RigAnimation.keyframes(
        rig.root, "opacity", values: [0, 1], times: [0, 1], duration: 0.2, repeats: false)
      RigAnimation.keyframes(
        rig.stage, "transform.scale", values: [0.65, 1.1, 1], times: [0, 0.6, 1], duration: 0.4,
        repeats: false)
      RigAnimation.keyframes(
        rig.dust, "opacity", values: [0.8, 0], times: [0, 1], duration: 0.45, repeats: false)
      RigAnimation.keyframes(
        rig.dust, "transform.scale", values: [0.7, 1.7], times: [0, 1], duration: 0.45,
        repeats: false)
    }
    library.register(.hang) { rig in
      RigAnimation.swing(rig.stage, "transform.rotation.z", from: -0.018, to: 0.018, duration: 1.4)
      RigAnimation.swing(rig.leftFoot, "transform.rotation.z", from: -0.12, to: 0.12, duration: 0.9)
      RigAnimation.swing(
        rig.rightFoot, "transform.rotation.z", from: 0.12, to: -0.12, duration: 1.1)
    }
    library.register(.climb) { rig in
      RigAnimation.swing(
        rig.secondaryGrip, "transform.translation.y", from: -3, to: 5, duration: 0.22)
      RigAnimation.swing(rig.stage, "transform.translation.y", from: -2, to: 2, duration: 0.22)
      RigAnimation.swing(
        rig.leftFoot, "transform.rotation.z", from: -0.45, to: 0.20, duration: 0.22)
      RigAnimation.swing(
        rig.rightFoot, "transform.rotation.z", from: 0.20, to: -0.45, duration: 0.22)
      RigAnimation.swing(rig.head, "transform.rotation.z", from: -0.035, to: 0.025, duration: 0.44)
    }
    library.register(.hangCatch) { rig in
      RigAnimation.keyframes(
        rig.stage, "transform.translation.y", values: [0, -7, 2, 0], times: [0, 0.2, 0.55, 1],
        duration: 0.55, repeats: false)
      RigAnimation.keyframes(
        rig.stage, "transform.rotation.z", values: [0, -0.07, 0.04, 0], times: [0, 0.2, 0.55, 1],
        duration: 0.55, repeats: false)
      RigAnimation.swing(rig.leftFoot, "transform.rotation.z", from: -0.4, to: 0.2, duration: 0.2)
      RigAnimation.swing(rig.rightFoot, "transform.rotation.z", from: 0.2, to: -0.4, duration: 0.2)
    }
    library.register(.snap) { rig in
      rig.delight.opacity = 1
      RigAnimation.keyframes(
        rig.stage, "transform.scale", values: [1, 0.86, 1.16, 0.97, 1],
        times: [0, 0.18, 0.48, 0.78, 1], duration: 0.55, repeats: false)
      RigAnimation.keyframes(
        rig.delight, "opacity", values: [0, 1, 0.8, 0], times: [0, 0.2, 0.6, 1], duration: 0.7,
        repeats: false)
    }
    library.registerReducedMotion(.snap) { rig in
      rig.delight.opacity = 1
    }
    library.register(.listen) { rig in
      rig.delight.opacity = 1
      RigAnimation.swing(rig.head, "transform.rotation.z", from: -0.06, to: 0.06, duration: 0.38)
      RigAnimation.swing(rig.stage, "transform.translation.y", from: 0, to: 2.2, duration: 0.38)
      RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: 0.35, to: 0.75, duration: 0.28)
      RigAnimation.swing(rig.delight, "opacity", from: 0.35, to: 0.95, duration: 0.65)
    }
    library.registerReducedMotion(.listen) { rig in
      rig.delight.opacity = 1
    }
    library.register(.watch) { rig in
      RigAnimation.swing(rig.head, "transform.rotation.z", from: -0.11, to: 0.11, duration: 0.95)
      RigAnimation.swing(rig.stage, "transform.translation.y", from: 0, to: 1.5, duration: 0.95)
      RigAnimation.swing(
        rig.accessory, "transform.rotation.z", from: -0.05, to: 0.05, duration: 0.95)
    }
    library.register(.focus) { rig in
      RigAnimation.swing(rig.head, "transform.rotation.z", from: -0.03, to: 0.03, duration: 1.1)
      RigAnimation.swing(rig.leftArm, "transform.rotation.z", from: -0.35, to: -0.1, duration: 0.24)
      RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: 0.1, to: 0.35, duration: 0.24)
    }
    for pose in [AttachmentPose.hangingLeft, .hangingRight] {
      library.registerVariant(.walk, pose: pose, clip: .climb)
      for id in [AnimationID.idle, .meditate, .listen, .watch, .focus] {
        library.registerVariant(id, pose: pose, clip: .hang)
      }
      for id in [AnimationID.balance, .brace, .scramble, .land, .happy, .wave, .snap] {
        library.registerVariant(id, pose: pose, clip: .hangCatch)
      }
    }
  }
}
