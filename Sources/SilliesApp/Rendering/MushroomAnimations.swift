import QuartzCore
import SilliesCore

@MainActor
enum MushroomAnimations {
  static let water: AnimationID = "sprout.water"
  private static let capSway = RigAnimation.Oscillation(
    keyPath: "transform.rotation.z", from: -0.035, to: 0.035, duration: 1.8)
  private static let capBounce = RigAnimation.Oscillation(
    keyPath: "transform.translation.y", from: 0, to: 2, duration: 0.3)
  private static let objects = RigAnimation.Sequence(
    keyPath: "opacity", values: [0, 1, 1, 0], times: [0, 0.15, 0.82, 1], duration: 2.4)
  private static let pour = RigAnimation.Sequence(
    keyPath: "transform.rotation.z", values: [0, 0.35, 0.35, 0], times: [0, 0.2, 0.8, 1],
    duration: 2.4)
  private static let trickle = RigAnimation.Sequence(
    keyPath: "transform.translation.y", values: [2, -4], times: [0, 1], duration: 0.5)
  private static let grow = RigAnimation.Sequence(
    keyPath: "transform.scale.y", values: [0.65, 1, 1], times: [0, 0.7, 1], duration: 2.4)

  static func register(in library: AnimationLibrary) {
    library.register(.idle, characterID: "sprout", clip: settleCap)
    library.register(.walk, characterID: "sprout") { rig in
      guard let mushroom = rig as? MushroomRig else { return }
      CreatureMotion.waddle(rig)
      RigAnimation.oscillate(mushroom.cap, capBounce)
    }
    library.register(.hang, characterID: "sprout", clip: settleCap)
    library.register(.climb, characterID: "sprout") { rig in
      CreatureMotion.climb(rig)
      settleCap(rig)
    }
    library.register(.hangCatch, characterID: "sprout") { rig in
      CreatureMotion.catchLedge(rig)
      settleCap(rig)
    }
    library.registerSignature(water, characterID: "sprout", clip: waterSeedling)
  }

  private static func settleCap(_ rig: CharacterRig) {
    guard let mushroom = rig as? MushroomRig else { return }
    CreatureMotion.blink(rig)
    RigAnimation.oscillate(mushroom.cap, capSway)
  }

  private static func waterSeedling(_ rig: CharacterRig) {
    guard let mushroom = rig as? MushroomRig else { return }
    for object in [mushroom.wateringCan, mushroom.seedling, mushroom.droplets] {
      RigAnimation.play(object, objects)
    }
    RigAnimation.play(mushroom.wateringCan, pour)
    RigAnimation.loop(mushroom.droplets, trickle)
    RigAnimation.play(mushroom.seedling, grow)
    settleCap(rig)
  }
}
