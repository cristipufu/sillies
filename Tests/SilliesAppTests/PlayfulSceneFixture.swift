import AppKit
import QuartzCore
import SilliesCore
import Testing

@testable import SilliesApp

@MainActor
final class PlayfulSceneFixture {
  let catalog: PlayfulSceneCatalog
  let window: CGRect
  let visible: CGRect
  let companions: [CompanionInstance]
  let coordinator: PlayfulSceneCoordinator

  init() throws {
    let catalog = try PlayfulSceneCatalog()
    self.catalog = catalog
    let visible = CompanionPanel.visibleFrame()
    self.visible = visible
    let window = CGRect(
      x: visible.minX + 160, y: visible.minY + 80,
      width: min(650, visible.width - 420), height: max(260, visible.height - 430))
    self.window = window
    let characters = try CharacterCatalog()
    let animations = AnimationLibrary()
    let surface = PerchSurface(window: window, visibleFrame: visible, characterSize: 64)
    let definitions = characters.characters.filter { ["mochi", "kiko"].contains($0.id) }
    companions = try definitions.enumerated().map { index, definition in
      let rig = try #require(RendererRegistry().make(definition.renderer))
      let pet = CompanionInstance(
        definition: definition, rig: rig, size: 64,
        seed: UInt64(index + 1), transitions: TransitionLibrary())
      pet.updateAttachment(.init(surface: surface, windowID: 777, windowLayer: 0))
      _ = pet.configureSurface(surface, window: window, display: visible)
      pet.place(at: surface.point(at: Double(index + 1) / Double(definitions.count + 1)))
      pet.presentation.show(reducedMotion: true)
      return pet
    }
    coordinator = PlayfulSceneCoordinator(catalog: catalog, animations: animations, seed: 7)
    coordinator.configure(.animated, at: 0)
  }

  func start(_ id: String, at time: Double = 0) throws {
    coordinator.cancel(.restorePerches)
    let participants = try companions.map { pet in
      PlayfulSceneParticipant(
        id: pet.definition.id, profile: try #require(pet.definition.playful),
        surface: try #require(pet.surface), position: pet.position, windowID: pet.attachedWindowID)
    }
    let started = coordinator.preview(
      id,
      opportunity: .init(
        time: time, trigger: .ambient,
        participants: participants, window: window, visibleFrame: visible), companions: companions)
    try #require(started, "Could not start \(id)")
  }

  func plan(_ id: String) throws -> PlayfulScenePlan {
    let scene = try #require(catalog.scenes.first { $0.id == id })
    let participants = try companions.prefix(scene.participants).map { pet in
      PlayfulSceneParticipant(
        id: pet.definition.id, profile: try #require(pet.definition.playful),
        surface: try #require(pet.surface), position: pet.position, windowID: pet.attachedWindowID)
    }
    return try #require(
      PlayfulSceneLayout.plan(
        .init(
          definition: scene, participants: participants, bystanders: [], window: window,
          visibleFrame: visible, message: "")))
  }

  func stop() {
    coordinator.stop()
    for pet in companions { pet.closeAllPanels() }
  }

  func sampleAnimations(at elapsed: Double, phase: Int, clock: PlayfulPreviewClock) {
    let layers =
      companions.compactMap { $0.view.layer }
      + coordinator.propPreviews.compactMap { $0.0.layer }
    clock.sample(layers, phase: phase, elapsed: elapsed)
  }

  func snapshot(named name: String, canvas requestedCanvas: CGRect? = nil, caption: String? = nil)
    throws
  {
    let views =
      companions.map { ($0.view as NSView, $0.panel.frame) }
      + coordinator.propPreviews
    let header = CGRect(x: window.minX, y: window.maxY - 70, width: window.width, height: 70)
    let canvas =
      requestedCanvas ?? views.reduce(header) { $0.union($1.1) }.insetBy(dx: -24, dy: -24)
    let scale = 2.0
    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width * scale), pixelsHigh: Int(canvas.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let graphics = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -canvas.minX, y: -canvas.minY)
    NSColor(hex: "EDE9F3").setFill()
    canvas.fill()
    NSColor(hex: "FFFCF8").setFill()
    NSBezierPath(roundedRect: window, xRadius: 12, yRadius: 12).fill()
    ("Sillies · \(caption ?? name)" as NSString).draw(
      at: CGPoint(x: window.minX + 24, y: window.maxY - 32),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor(hex: "8C8399"),
      ])
    for (view, frame) in views.sorted(by: {
      ($0.0.window?.level.rawValue ?? 0) < ($1.0.window?.level.rawValue ?? 0)
    }) {
      guard let layer = view.layer else { continue }
      context.saveGState()
      context.translateBy(x: frame.minX, y: frame.minY)
      context.clip(to: CGRect(origin: .zero, size: frame.size))
      context.beginTransparencyLayer(auxiliaryInfo: nil)
      (layer.presentation() ?? layer).render(in: context)
      context.endTransparencyLayer()
      context.restoreGState()
    }
    NSGraphicsContext.restoreGraphicsState()
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("build/playful-previews")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let output = directory.appendingPathComponent("\(name).png")
    try FileManager.default.createDirectory(
      at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: output, options: .atomic)
  }
}
