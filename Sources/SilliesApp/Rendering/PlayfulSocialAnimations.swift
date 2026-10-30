import QuartzCore
import SilliesCore

@MainActor
enum PlayfulSocialAnimations {
  static func register(in library: AnimationLibrary) {
    library.register("scene.tug") { rig in
      rig.leftArm.opacity = 0
      rig.rightArm.opacity = 0
      rig.preparePlayfulProps().contact.gripRope()
      RigAnimation.swing(rig.torso, "transform.rotation.z", from: 0.02, to: 0.07, duration: 0.55)
      RigAnimation.swing(rig.head, "transform.rotation.z", from: 0.04, to: 0.12, duration: 0.55)
    }
    library.register("scene.sit") { rig in
      rig.preparePlayfulProps().ledge.opacity = 1
      rig.torso.transform = CATransform3DMakeTranslation(0, 12, 0)
      rig.head.transform = CATransform3DMakeTranslation(0, 12, 0)
      rig.leftArm.transform = CATransform3DMakeTranslation(0, 12, 0)
      rig.rightArm.transform = CATransform3DMakeTranslation(0, 12, 0)
      rig.leftFoot.transform = CATransform3DMakeTranslation(0, 6, 0)
      rig.rightFoot.transform = CATransform3DMakeTranslation(0, 6, 0)
      RigAnimation.swing(rig.leftFoot, "transform.rotation.z", from: -0.12, to: 0.2, duration: 0.7)
      RigAnimation.swing(rig.rightFoot, "transform.rotation.z", from: 0.2, to: -0.12, duration: 0.7)
    }
    library.register("scene.warmHands") { rig in
      rig.rightArm.transform = CATransform3DMakeRotation(0.9, 0, 0, 1)
      rig.leftArm.transform = CATransform3DMakeRotation(-0.5, 0, 0, 1)
      RigAnimation.swing(rig.head, "transform.rotation.z", from: -0.03, to: 0.04, duration: 1.5)
      RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: 0.75, to: 0.95, duration: 1)
    }
    library.register("scene.throw") { rig in
      RigAnimation.play(
        rig.rightArm,
        .init(
          keyPath: "transform.rotation.z", values: [-0.4, 1.8, 0.4],
          times: [0, 0.4, 1], duration: 1.1))
      RigAnimation.play(
        rig.stage,
        .init(
          keyPath: "transform.rotation.z", values: [0.08, -0.08, 0],
          times: [0, 0.45, 1], duration: 1.1))
    }
    library.register("scene.lift") { rig in
      rig.leftArm.transform = CATransform3DMakeRotation(-0.8, 0, 0, 1)
      rig.rightArm.transform = CATransform3DMakeRotation(0.8, 0, 0, 1)
      RigAnimation.swing(rig.stage, "transform.scale.y", from: 0.88, to: 0.95, duration: 0.5)
      RigAnimation.swing(rig.head, "transform.translation.x", from: -1.2, to: 1.2, duration: 0.08)
    }
    for id: AnimationID in [
      "scene.tug", "scene.sit", "scene.warmHands", "scene.throw", "scene.lift",
    ] {
      library.registerReducedMotion(id) { rig in
        rig.delight.opacity = 1
        if id == "scene.sit" { rig.preparePlayfulProps().ledge.opacity = 1 }
      }
    }
  }
}
