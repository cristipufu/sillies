import AppKit
import SilliesCore
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func chatNativeBubbleRetainsTransparencyAcrossThemeUpdates() async throws {
  let appearance = ThemeEnvironment()
  let controller = ChatSessionWindowController(appearance: appearance)
  let session = ChatWindowFixture.makeSession()
  controller.prepare(session, openSettings: { _ in }, renderer: "cat")
  let window = try #require(controller.window)
  defer {
    controller.close()
    session.finish {}
  }
  #expect(!window.isVisible)
  #expect(!window.isOpaque)
  #expect(window.backgroundColor.alphaComponent == 0)
  appearance.update(SilliesTheme(contrast: .increased))
  #expect(window.backgroundColor.alphaComponent == 0)
  let view = try #require(window.contentView)
  view.frame = CGRect(origin: .zero, size: ChatWindowLayout.initialSize)
  view.layoutSubtreeIfNeeded()
  let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
  view.cacheDisplay(in: view.bounds, to: image)
  for point in [(1, 1), (image.pixelsWide - 2, 1), (1, image.pixelsHigh - 2)] {
    #expect(try #require(image.colorAt(x: point.0, y: point.1)).alphaComponent < 0.01)
  }
  #expect(
    try #require(image.colorAt(x: image.pixelsWide / 2, y: image.pixelsHigh / 2)).alphaComponent
      > 0.99)
  if ProcessInfo.processInfo.environment["SILLIES_SKILL_UI_SNAPSHOTS"] == "1" {
    let data = try #require(image.representation(using: .png, properties: [:]))
    try data.write(
      to: FileManager.default.temporaryDirectory.appendingPathComponent(
        "sillies-native-chat-bubble.png"))
  }
}

@Test @MainActor func radialMenuIgnoresGapsDismissesOutsideAndStopsMonitoring() {
  let panel = SkillFloatingPanel(
    contentRect: CGRect(x: 0, y: 0, width: 300, height: 300), ignoresMouseEvents: true)
  defer { panel.close() }
  let interaction = RadialMenuInteraction()
  var dismissed = false
  interaction.start(panel: panel, regions: [.init(center: CGPoint(x: 150, y: 150), titleWidth: 80)])
  {
    dismissed = true
    interaction.stop()
  }
  #expect(interaction.isMonitoring)
  interaction.refresh(at: CGPoint(x: 150, y: 162))
  #expect(!panel.ignoresMouseEvents)
  interaction.handlePointer(.leftMouseDown, at: CGPoint(x: 150, y: 162))
  #expect(!dismissed)
  interaction.refresh(at: CGPoint(x: 30, y: 30))
  #expect(panel.ignoresMouseEvents)
  interaction.handlePointer(.leftMouseDown, at: CGPoint(x: 30, y: 30))
  #expect(dismissed)
  #expect(!interaction.isMonitoring)
  #expect(panel.ignoresMouseEvents)
}

@Test @MainActor func directActionsUseTheSharedOrbitalArtworkInBothAppearances() throws {
  let layout = CompanionActionMenuLayout(
    anchor: CGPoint(x: 400, y: 400), count: 4,
    itemSize: CGSize(width: 110, height: 100),
    visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 800))
  for scheme in [ColorScheme.light, .dark] {
    try renderSkillInterface(
      CompanionDirectMenuView(layout: layout, perform: { _ in })
        .environment(\.colorScheme, scheme), size: layout.frame.size,
      name: "sillies-direct-wheel-\(scheme)")
  }
}

@Test @MainActor func directMenuNativePresentationDismissesAndReleasesTheCompanion() throws {
  let definition = try #require(try CharacterCatalog().characters.first { $0.id == "mochi" })
  let appearance = ThemeEnvironment()
  let pet = CompanionInstance(
    configuration: .init(definition: definition, size: 64, seed: 1),
    rig: CatRig(), transitions: TransitionLibrary(), appearance: appearance)
  let menu = CompanionDirectMenu(appearance: appearance)
  defer {
    menu.close()
    pet.closeAllPanels()
  }
  pet.place(at: CGPoint(x: 500, y: 500))
  pet.presentation.show(reducedMotion: true)
  menu.show(for: pet) { _ in }
  try DisplayFrameSequence.presentCreatedWindows()
  let window = try #require(menu.windowNumber.flatMap { NSApp.window(withWindowNumber: $0) })
  #expect(window.isVisible)
  #expect(window.canBecomeKey)
  #expect(window.level == CompanionPanel.hudLevel(forWindowLayer: pet.attachedWindowLayer))
  #expect(window.backgroundColor.alphaComponent == 0)
  #expect(pet.holdsConversationPerch)
  let escape = try #require(
    NSEvent.keyEvent(
      with: .keyDown, location: .zero,
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber,
      context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
      keyCode: 53))
  NSApp.sendEvent(escape)
  #expect(!window.isVisible)
  #expect(!pet.holdsConversationPerch)
  #expect(menu.windowNumber == nil)
}
