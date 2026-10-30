import QuartzCore
import SilliesCore

@MainActor
enum PlayfulAnimations {
  private enum Timing {
    static let beat = 0.3
    static let sweep = 0.65
    static let monocleGrowth = 3.0
  }

  static func register(in library: AnimationLibrary) {
    library.register("scene.monocle") { rig in
      let lens = rig.preparePlayfulProps().monocle.layer
      lens.opacity = 1
      lens.transform = CATransform3DMakeScale(1.5, 1.5, 1)
      RigAnimation.keyframes(
        lens, "transform.scale", values: [0.3, 0.75, 1.55, 1.5],
        times: [0, 0.3, 0.85, 1], duration: Timing.monocleGrowth, repeats: false)
      RigAnimation.play(
        rig.head,
        .init(
          keyPath: "transform.rotation.z", values: [0, -0.04, 0.1, 0.06], times: [0, 0.3, 0.8, 1],
          duration: Timing.monocleGrowth))
    }
    library.register("scene.sweep") { rig in
      rig.preparePlayfulProps().sweep.play()
      rig.leftArm.opacity = 0
      rig.rightArm.opacity = 0
      RigAnimation.swing(
        rig.head, "transform.rotation.z", from: -0.06, to: 0.02, duration: Timing.sweep)
      rig.dust.opacity = 0.35
      RigAnimation.swing(
        rig.dust, "transform.translation.x", from: 8, to: -15, duration: Timing.sweep)
      RigAnimation.swing(rig.dust, "opacity", from: 0.35, to: 0, duration: Timing.sweep)
    }
    library.register("scene.sign") { rig in
      RigAnimation.swing(rig.leftArm, "transform.rotation.z", from: -1.3, to: -1.6, duration: 0.4)
      RigAnimation.swing(rig.head, "transform.rotation.z", from: -0.04, to: 0.04, duration: 0.8)
    }
    for id: AnimationID in [
      "scene.monocle", "scene.sweep",
      "scene.sign",
    ] {
      library.registerReducedMotion(id) { rig in
        rig.delight.opacity = 1
        if id == "scene.monocle" { rig.preparePlayfulProps().monocle.layer.opacity = 1 }
        if id == "scene.sweep" {
          rig.preparePlayfulProps().sweep.show()
          rig.leftArm.opacity = 0
          rig.rightArm.opacity = 0
        }
      }
    }
  }

}
