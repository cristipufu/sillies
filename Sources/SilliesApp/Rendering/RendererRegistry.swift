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
  }

  func register(_ id: String, factory: @escaping Factory) { factories[id] = factory }
  func make(_ id: String) -> CharacterRig? { factories[id]?() }
  func contains(_ id: String) -> Bool { factories[id] != nil }
}
