import AppKit
import SilliesCore
import Testing

@testable import SilliesApp

@Test func boundWindowMetadataDistinguishesCoveringFromBackgroundWindows() throws {
  let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
  let target = windowEntry(id: 1, frame: frame)
  let covering = windowEntry(id: 2, frame: frame.insetBy(dx: -40, dy: -40))
  let hidden = BoundWindowSnapshots.resolve(
    entries: [covering, target], windowIDs: [1], primaryScreenTop: 1000)
  #expect(hidden[1]?.visibility == .hidden)
  let visible = BoundWindowSnapshots.resolve(
    entries: [target, covering], windowIDs: [1], primaryScreenTop: 1000)
  #expect(visible[1]?.visibility == .visible)
  var minimized = target
  minimized[kCGWindowIsOnscreen as String] = false
  let minimizedResult = BoundWindowSnapshots.resolve(
    entries: [minimized], windowIDs: [1], primaryScreenTop: 1000)
  #expect(minimizedResult[1]?.visibility == .hidden)
  let token = WindowTrackingExclusions.transparentOverlays.register(2)
  withExtendedLifetime(token) {
    let overlay = BoundWindowSnapshots.resolve(
      entries: [covering, target], windowIDs: [1], primaryScreenTop: 1000)
    #expect(overlay[1]?.visibility == .visible)
  }
}

@Test @MainActor func boundCompanionAndHUDHideTogetherWithoutEndingTheirSkill() throws {
  _ = NSApplication.shared
  let window = NSWindow(
    contentRect: CGRect(x: 200, y: 200, width: 600, height: 400), styleMask: [.titled],
    backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer { window.close() }
  let definition = try #require(try CharacterCatalog().characters.first { $0.id == "mochi" })
  let pet = CompanionInstance(
    definition: definition, rig: CatRig(), size: 64, seed: 1, transitions: TransitionLibrary())
  defer { pet.closeAllPanels() }
  var target = WindowTargetCandidate(
    windowID: UInt32(window.windowNumber), processID: ProcessInfo.processInfo.processIdentifier,
    appName: "Meeting", frame: window.frame)
  pet.updateBinding(.active(target: target, skill: .listen, startedAt: 0))
  pet.place(at: CGPoint(x: 400, y: window.frame.maxY + 1))
  pet.presentation.show(reducedMotion: true)
  pet.refreshHUD()
  #expect(pet.panel.level == .normal)
  #expect(pet.panel.isVisible)
  #expect(pet.hud.isVisible)
  let hudWindow = try #require(pet.hud.windowNumber.flatMap { NSApp.window(withWindowNumber: $0) })
  #expect(hudWindow.level == CompanionPanel.hudLevel(forWindowLayer: 0))
  target.isVisible = false
  pet.updateBinding(.active(target: target, skill: .listen, startedAt: 0))
  pet.presentation.show(reducedMotion: true)
  pet.refreshHUD()
  #expect(!pet.panel.isVisible)
  #expect(!pet.hud.isVisible)
  #expect(pet.bindingState.isBound)
  target.isVisible = true
  pet.updateBinding(.active(target: target, skill: .listen, startedAt: 0))
  pet.presentation.show(reducedMotion: true)
  pet.refreshHUD()
  #expect(pet.panel.isVisible)
  #expect(pet.hud.isVisible)
  pet.beginPickup(fallbackTarget: target)
  #expect(pet.panel.level == CompanionPanel.floatingOverlayLevel)
  let transcript = CompanionUtilityWindow(
    contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
  transcript.isReleasedWhenClosed = false
  defer { transcript.close() }
  #expect(transcript.level.rawValue > pet.panel.level.rawValue)
}

private func windowEntry(id: UInt32, frame: CGRect) -> [String: Any] {
  [
    kCGWindowNumber as String: id, kCGWindowOwnerPID as String: Int32(123),
    kCGWindowLayer as String: 0, kCGWindowIsOnscreen as String: true,
    kCGWindowAlpha as String: 1.0, kCGWindowBounds as String: frame.dictionaryRepresentation,
  ]
}
