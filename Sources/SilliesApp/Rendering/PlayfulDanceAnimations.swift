import QuartzCore
import SilliesCore

@MainActor
enum PlayfulDanceAnimations {
  private static let measure = 1.2
  private static let beats: [NSNumber] = [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1]

  static func register(in library: AnimationLibrary) {
    library.register("scene.danceIntro") { rig in
      RigAnimation.play(
        rig.head,
        .init(
          keyPath: "transform.rotation.z", values: [0, -0.14, -0.14, 0.06, 0],
          times: [0, 0.25, 0.55, 0.85, 1], duration: 0.8))
      RigAnimation.play(
        rig.stage,
        .init(
          keyPath: "transform.scale.y", values: [1, 1, 0.92, 1],
          times: [0, 0.55, 0.8, 1], duration: 0.8))
    }
    library.register("scene.dance", clip: dance)
    library.register("scene.bounceDance") { rig in
      dance(rig)
      cycle(rig.stage, "transform.translation.y", [0, 9, 0, 2, 0, 9, 0, 2, 0])
    }
    library.register("scene.robotDance") { rig in
      dance(rig)
      cycle(rig.head, "transform.rotation.z", [0, -0.12, -0.12, 0, 0, 0.12, 0.12, 0, 0])
    }
    library.register("scene.danceFinish") { rig in
      rig.leftArm.transform = CATransform3DMakeRotation(-2.1, 0, 0, 1)
      rig.rightArm.transform = CATransform3DMakeRotation(2.1, 0, 0, 1)
      rig.eyes.opacity = 0
      rig.closedEyes.opacity = 1
      rig.delight.opacity = 1
      RigAnimation.play(
        rig.stage,
        .init(
          keyPath: "transform.scale.y", values: [0.9, 1.08, 0.98, 1],
          times: [0, 0.25, 0.65, 1], duration: 0.6))
    }
    for id: AnimationID in [
      "scene.danceIntro", "scene.dance", "scene.bounceDance", "scene.robotDance",
      "scene.danceFinish",
    ] {
      library.registerReducedMotion(id) { rig in rig.delight.opacity = 1 }
    }
  }

  private static func dance(_ rig: CharacterRig) {
    cycle(rig.stage, "transform.rotation.z", [0, -0.07, -0.1, -0.04, 0, 0.07, 0.1, 0.04, 0])
    cycle(rig.stage, "transform.translation.x", [0, -3, -5, -2, 0, 3, 5, 2, 0])
    cycle(rig.stage, "transform.translation.y", [0, 4, 0, 1, 0, 4, 0, 1, 0])
    cycle(rig.stage, "transform.scale.y", [0.96, 1.03, 0.96, 1, 0.96, 1.03, 0.96, 1, 0.96])
    cycle(rig.head, "transform.rotation.z", [0, 0.08, 0.1, 0.02, 0, -0.08, -0.1, -0.02, 0])
    cycle(
      rig.leftArm, "transform.rotation.z", [-0.2, -1.2, -1.5, -1.1, -0.2, -0.4, -0.7, -0.4, -0.2])
    cycle(rig.rightArm, "transform.rotation.z", [0.2, 0.4, 0.7, 0.4, 0.2, 1.2, 1.5, 1.1, 0.2])
    cycle(rig.leftFoot, "transform.translation.y", [0, 7, 2, 0, 0, 0, 0, 0, 0])
    cycle(rig.rightFoot, "transform.translation.y", [0, 0, 0, 0, 0, 7, 2, 0, 0])
    cycle(rig.leftFoot, "transform.rotation.z", [0, -0.25, -0.08, 0, 0, 0.08, 0, 0, 0])
    cycle(rig.rightFoot, "transform.rotation.z", [0, -0.08, 0, 0, 0, 0.25, 0.08, 0, 0])
  }

  private static func cycle(_ layer: CALayer, _ key: String, _ values: [Double]) {
    RigAnimation.loop(layer, .init(keyPath: key, values: values, times: beats, duration: measure))
  }
}
