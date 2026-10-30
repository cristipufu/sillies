import AppKit
import QuartzCore
import SilliesCore
import Testing

@testable import SilliesApp

@Test @MainActor func crowdedCrewsWaitForSpaceAndKeepTheirGreetings() throws {
  let suiteName = "app.sillies.test.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let size = AppSettings.maxSize
  let displayWidth = NSScreen.main?.visibleFrame.width ?? 1440
  let count = Int(displayWidth / PerchSpacing.separation(between: size, and: size)) + 4
  let original = try #require(CharacterCatalog().characters.first)
  let characters = (0..<count).map { index in
    CharacterDefinition(
      id: "crowd-\(index)", name: "Companion \(index)", subtitle: "", bio: "",
      renderer: "crowd", accent: original.accent, speed: original.speed, order: index,
      reactions: original.reactions)
  }
  let renderers = RendererRegistry()
  var rigs: [CharacterRig] = []
  renderers.register("crowd") {
    let rig = CatRig()
    rigs.append(rig)
    return rig
  }
  let settings = AppSettings(defaults: defaults)
  settings.size = size
  settings.followsWindows = false
  settings.reduceMotion = true
  settings.enabledCharacters = Set(characters.map(\.id))
  let controller = try CompanionController(
    settings: settings,
    assets: .init(catalog: CharacterCatalog(characters: characters), renderers: renderers),
    services: .init(accessibility: .disabled))
  controller.start()
  defer { controller.stop() }

  #expect(controller.diagnostics.visibleCount < count)
  expectDistinctVisibleStops(controller, size: size)
  controller.playReaction(.neighbor)
  #expect(controller.playedAnimations[.happy, default: 0] > 0)
  expectDistinctVisibleStops(controller, size: size)

  for (index, attachment) in controller.attachmentDiagnostics.enumerated() where !attachment.visible
  {
    #expect(layersWithoutAnimations(rigs[index].root))
  }
  settings.enabledCharacters = Set(characters.prefix(2).map(\.id))
  #expect(controller.diagnostics.visibleCount == 2)
  expectDistinctVisibleStops(controller, size: size)
}

@MainActor
private func expectDistinctVisibleStops(_ controller: CompanionController, size: Double) {
  let visible = controller.attachmentDiagnostics.filter(\.visible)
  for (index, first) in visible.enumerated() {
    for second in visible.dropFirst(index + 1) {
      #expect(
        abs(first.point.x - second.point.x) + 0.001
          >= PerchSpacing.separation(between: size, and: size))
    }
  }
}

@MainActor
private func layersWithoutAnimations(_ layer: CALayer) -> Bool {
  layer.animationKeys() == nil && (layer.sublayers ?? []).allSatisfy(layersWithoutAnimations)
}
