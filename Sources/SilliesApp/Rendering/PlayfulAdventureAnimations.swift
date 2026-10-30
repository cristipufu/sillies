import QuartzCore
import SilliesCore

@MainActor
enum PlayfulAdventureAnimations {
  static func register(in library: AnimationLibrary) {
    library.register("scene.shove") { rig in
      rig.leftArm.opacity = 0
      rig.rightArm.opacity = 0
      rig.preparePlayfulProps().contact.shove()
      RigAnimation.play(
        rig.torso,
        .init(
          keyPath: "transform.rotation.z", values: [0.04, -0.12, 0],
          times: [0, 0.35, 1], duration: 0.9))
      RigAnimation.play(
        rig.head,
        .init(
          keyPath: "transform.translation.x", values: [-2, 5, 0],
          times: [0, 0.35, 1], duration: 0.9))
    }
    library.register("scene.clamber") { rig in
      rig.leftArm.opacity = 0
      rig.rightArm.opacity = 0
      rig.preparePlayfulProps().clamber()
    }
    library.register("scene.fall") { rig in
      RigAnimation.swing(rig.leftArm, "transform.rotation.z", from: -1.8, to: -2.4, duration: 0.16)
      RigAnimation.swing(rig.rightArm, "transform.rotation.z", from: 1.8, to: 2.4, duration: 0.16)
      RigAnimation.swing(rig.stage, "transform.rotation.z", from: -0.12, to: 0.12, duration: 0.2)
    }
    library.register("scene.parachute") { rig in
      rig.holdPlayfulProp(at: PlayfulPropLayout.parachuteLeftGrip, hand: .left, angle: -2.2)
      rig.holdPlayfulProp(at: PlayfulPropLayout.parachuteRightGrip, angle: 2.2)
      RigAnimation.swing(rig.head, "transform.rotation.z", from: -0.045, to: 0.045, duration: 1.2)
      RigAnimation.swing(rig.leftFoot, "transform.rotation.z", from: -0.12, to: 0.08, duration: 1.2)
      RigAnimation.swing(
        rig.rightFoot, "transform.rotation.z", from: 0.08, to: -0.12, duration: 1.2)
    }
    library.register("scene.grumpy") { rig in
      rig.eyes.opacity = 0
      rig.closedEyes.opacity = 1
      RigAnimation.swing(rig.head, "transform.rotation.z", from: -0.08, to: 0.08, duration: 0.3)
    }
    for id: AnimationID in [
      "scene.shove", "scene.fall", "scene.clamber", "scene.parachute", "scene.grumpy",
    ] {
      library.registerReducedMotion(id) { rig in
        rig.eyes.opacity = 0
        rig.closedEyes.opacity = 1
        rig.delight.opacity = 1
      }
    }
  }
}
