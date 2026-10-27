import SilliesCore

@MainActor
final class RendererRegistry {
  typealias Factory = @MainActor () -> CharacterRig
  private var factories: [String: Factory] = [:]

  init() {
    register("cat", factory: CatRig.init)
    register("ninja", factory: NinjaRig.init)
    register("frog", factory: FrogRig.init)
    register("robot", factory: RobotRig.init)
    register("ghost", factory: GhostRig.init)
    register("octopus", factory: OctopusRig.init)
    register("mushroom", factory: MushroomRig.init)
    register("axolotl", factory: AxolotlRig.init)
    register("penguin", factory: PenguinRig.init)
    register("dragon", factory: DragonRig.init)
    register("hedgehog", factory: HedgehogRig.init)
    register("bunny", factory: BunnyRig.init)
  }

  func register(_ id: String, factory: @escaping Factory) { factories[id] = factory }
  func make(_ id: String) -> CharacterRig? { factories[id]?() }
  func contains(_ id: String) -> Bool { factories[id] != nil }
}
