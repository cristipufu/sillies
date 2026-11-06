import AppKit
import SilliesCore
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func chatNativeBubbleRetainsTransparencyAcrossThemeUpdates() async throws {
  let appearance = ThemeEnvironment()
  let controller = ChatSessionWindowController(
    appearance: appearance, reading: .init(size: .standard))
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
  interaction.start(
    panel: panel, localRegions: [.init(center: CGPoint(x: 150, y: 150), titleWidth: 80)]
  ) {
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

@Test @MainActor func skillOverlayKeepsItsAnchorWhenTransparentPaddingCrossesTheScreenEdge() throws
{
  let screen = try #require(NSScreen.main)
  let visible = screen.visibleFrame
  let frame = CGRect(x: visible.midX - 180, y: visible.maxY - 80, width: 360, height: 360)
  let panel = SkillFloatingPanel(
    contentRect: frame, ignoresMouseEvents: true,
    level: CompanionPanel.hudLevel(forWindowLayer: 0))
  defer { panel.close() }
  #expect(panel.constrainFrameRect(frame, to: screen) == frame)
}

@Test @MainActor func radialMenuTracksRenderedButtonsAfterItsPanelMoves() throws {
  let panel = SkillFloatingPanel(
    contentRect: CGRect(x: 200, y: 300, width: 300, height: 300), ignoresMouseEvents: true)
  defer { panel.close() }
  let interaction = RadialMenuInteraction()
  defer { interaction.stop() }
  var dismissed = false
  interaction.start(
    panel: panel, localRegions: [.init(center: CGPoint(x: 150, y: 150), titleWidth: 80)]
  ) { dismissed = true }
  #expect(panel.acceptsMouseMovedEvents)
  panel.setFrameOrigin(CGPoint(x: 400, y: 450))
  let click = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseDown, location: CGPoint(x: 150, y: 162), modifierFlags: [],
      timestamp: 1, windowNumber: panel.windowNumber, context: nil,
      eventNumber: 1, clickCount: 1, pressure: 1))
  #expect(interaction.handleLocalEvent(click) === click)
  #expect(!panel.ignoresMouseEvents)
  #expect(!dismissed)
  interaction.refresh(at: panel.convertPoint(toScreen: CGPoint(x: 30, y: 30)))
  #expect(panel.ignoresMouseEvents)
  interaction.stop()
  #expect(!panel.acceptsMouseMovedEvents)
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

@Test @MainActor func directMenuButtonsDispatchEveryActionAtTheTopScreenEdge() throws {
  let visible = try #require(NSScreen.main).visibleFrame
  let layout = CompanionActionMenuLayout(
    anchor: CGPoint(x: visible.midX, y: visible.maxY - 30), count: 4,
    itemSize: CGSize(width: 110, height: 100), visibleFrame: visible)
  let panel = SkillFloatingPanel(
    contentRect: layout.frame, ignoresMouseEvents: false,
    level: CompanionPanel.hudLevel(forWindowLayer: 0), focus: .keyboard)
  defer { panel.close() }
  var selected: [CompanionDirectAction] = []
  let view = ThemedHostingView(
    rootView: CompanionDirectMenuView(layout: layout) { selected.append($0) },
    appearance: ThemeEnvironment())
  view.sizingOptions = []
  panel.contentView = view
  view.frame = CGRect(origin: .zero, size: layout.frame.size)
  view.layoutSubtreeIfNeeded()
  let initialFrame = panel.frame
  let interaction = RadialMenuInteraction()
  defer { interaction.stop() }
  var dismissals = 0
  interaction.start(
    panel: panel,
    localRegions: zip(layout.centers, CompanionDirectAction.allCases).map { center, action in
      .init(
        center: CGPoint(x: center.x - layout.frame.minX, y: center.y - layout.frame.minY),
        titleWidth: action.titleWidth)
    }
  ) { dismissals += 1 }
  panel.orderFrontRegardless()
  panel.makeKey()
  try DisplayFrameSequence.presentCreatedWindows()
  #expect(panel.frame == initialFrame)
  for (action, center) in zip(CompanionDirectAction.allCases, layout.centers) {
    let iconOffset = (RadialMenuItemLayout.height - RadialMenuItemLayout.iconDiameter) / 2
    let icon = panel.convertPoint(fromScreen: CGPoint(x: center.x, y: center.y + iconOffset))
    let down = try menuMouseEvent(.leftMouseDown, at: icon, in: panel)
    let up = try menuMouseEvent(.leftMouseUp, at: icon, in: panel)
    NSApp.postEvent(up, atStart: true)
    NSApp.sendEvent(down)
    try DisplayFrameSequence.run(count: 2) { _ in }
    #expect(selected.last == action)
  }
  #expect(selected == CompanionDirectAction.allCases)
  #expect(dismissals == 0)
}

@MainActor private func menuMouseEvent(
  _ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow
) throws -> NSEvent {
  try #require(
    NSEvent.mouseEvent(
      with: type, location: point, modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
      context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
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
