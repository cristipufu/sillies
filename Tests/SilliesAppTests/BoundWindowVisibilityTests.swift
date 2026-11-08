import AppKit
import SilliesCore
import Testing

@testable import SilliesApp

@Test func boundVisibilityUsesOnScreenOrderInsteadOfTheUnorderedWindowInventory() throws {
  let target = windowEntry(id: 1, frame: CGRect(x: 196, y: 158, width: 1113, height: 696))
  let background = windowEntry(id: 2, frame: CGRect(x: 72, y: 87, width: 1289, height: 791))
  let snapshots = BoundWindowSnapshots.read(
    windowIDs: [1], primaryScreenTop: 982,
    source: .init(
      visibleWindows: { [target, background] },
      targetWindows: { _ in
        Issue.record("Visible windows do not require a second lookup")
        return nil
      }))
  #expect(snapshots[1]?.visibility == .visible)
}

@Test func boundVisibilitySeparatesHiddenWindowsFromConfirmedClosures() throws {
  let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
  let visible = windowEntry(id: 1, frame: frame)
  let hidden = windowEntry(id: 2, frame: frame)
  var requested: Set<CGWindowID> = []
  let snapshots = BoundWindowSnapshots.read(
    windowIDs: [1, 2, 3], primaryScreenTop: 1000,
    source: .init(
      visibleWindows: { [visible] },
      targetWindows: {
        requested = $0
        return [hidden]
      }))
  #expect(snapshots[1]?.visibility == .visible)
  #expect(snapshots[2]?.visibility == .hidden)
  #expect(snapshots[2]?.frame == CGRect(x: 100, y: 500, width: 600, height: 400))
  #expect(snapshots[3]?.visibility == .closed)
  #expect(requested == [2, 3])
}

@Test func boundVisibilityRetainsKnownWindowsWhenMetadataIsUnavailable() throws {
  let visible = windowEntry(id: 1, frame: CGRect(x: 100, y: 100, width: 600, height: 400))
  let unavailable = BoundWindowSnapshots.read(
    windowIDs: [1, 2], primaryScreenTop: 1000,
    source: .init(visibleWindows: { nil }, targetWindows: { _ in nil }))
  #expect(unavailable[1]?.visibility == .unavailable)
  #expect(unavailable[2]?.visibility == .unavailable)
  let partial = BoundWindowSnapshots.read(
    windowIDs: [1, 2], primaryScreenTop: 1000,
    source: .init(visibleWindows: { [visible] }, targetWindows: { _ in nil }))
  #expect(partial[1]?.visibility == .visible)
  #expect(partial[2]?.visibility == .unavailable)
  let empty = BoundWindowSnapshots.read(
    windowIDs: [], primaryScreenTop: 1000,
    source: .init(
      visibleWindows: {
        Issue.record("No windows were requested")
        return nil
      }, targetWindows: { _ in nil }))
  #expect(empty.isEmpty)
}

@Test func boundVisibilityCannotTreatTruncatedOrMalformedMetadataAsClosure() {
  let frame = CGRect(x: 10, y: 10, width: 500, height: 400)
  let entries = (1...300).map { windowEntry(id: UInt32($0), frame: frame) }
  // The target lies beyond the visible-stack inspection budget. Its exact lookup still finds it.
  let snapshot = BoundWindowSnapshots.read(
    windowIDs: [300], primaryScreenTop: 1000,
    source: .init(visibleWindows: { entries }, targetWindows: { _ in [entries[299]] }))
  #expect(snapshot[300]?.visibility == .hidden)
  let malformed = BoundWindowSnapshots.read(
    windowIDs: [300], primaryScreenTop: 1000,
    source: .init(
      visibleWindows: { [] },
      targetWindows: { _ in
        [[kCGWindowNumber as String: 300]]
      }))
  #expect(malformed[300]?.visibility == .unavailable)
}

@Test func boundWindowIdentityIncludesItsOwnerProcess() {
  let target = WindowTargetCandidate(windowID: 1, processID: 123, appName: "Meeting", frame: .zero)
  let reused = WindowTargetSnapshot(frame: .zero, title: nil, ownerPID: 456)
  #expect(reused.hasClosed(target))
  #expect(
    !WindowTargetSnapshot(frame: .zero, title: nil, visibility: .unavailable).hasClosed(target))
}

@Test(arguments: [CGWindowLevelKey.dockWindow, .statusWindow, .screenSaverWindow])
func systemOverlayBoundsDoNotHideABoundCompanion(_ layer: CGWindowLevelKey) throws {
  let target = windowEntry(id: 1, frame: CGRect(x: 100, y: 100, width: 600, height: 400))
  var systemOverlay = windowEntry(id: 2, frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
  systemOverlay[kCGWindowLayer as String] = Int(CGWindowLevelForKey(layer))
  let snapshots = BoundWindowSnapshots.resolve(
    entries: [systemOverlay, target], windowIDs: [1], primaryScreenTop: 982)
  #expect(snapshots[1]?.visibility == .visible)
}

@Test(arguments: [CGWindowLevelKey.floatingWindow, .modalPanelWindow])
func applicationPanelsStillOccludeBoundWindows(_ layer: CGWindowLevelKey) throws {
  let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
  let target = windowEntry(id: 1, frame: frame)
  var covering = windowEntry(id: 2, frame: frame)
  covering[kCGWindowLayer as String] = Int(CGWindowLevelForKey(layer))
  let snapshots = BoundWindowSnapshots.resolve(
    entries: [covering, target], windowIDs: [1], primaryScreenTop: 1000)
  #expect(snapshots[1]?.visibility == .hidden)
}

@Test func boundWindowRemainsVisibleBehindAnOrderedOutWebView() throws {
  // Teams keeps an ordered-out WebView with the meeting window's exact bounds.
  // CGWindowList omits kCGWindowIsOnscreen for that hidden backing window.
  let frame = CGRect(x: 245, y: 149, width: 1142, height: 715)
  let target = windowEntry(id: 1, frame: frame)
  var hiddenWebView = windowEntry(id: 2, frame: frame)
  hiddenWebView[kCGWindowOwnerPID as String] = Int32(456)
  hiddenWebView.removeValue(forKey: kCGWindowIsOnscreen as String)

  let snapshots = BoundWindowSnapshots.resolve(
    entries: [hiddenWebView, target], windowIDs: [1, 2], primaryScreenTop: 982)

  #expect(snapshots[1]?.visibility == .visible)
  #expect(snapshots[2]?.visibility == .hidden)
  let boundTarget = WindowTargetCandidate(
    windowID: 1, processID: 123, appName: "Meeting", frame: frame)
  let updatedTarget = try #require(snapshots[1]).updating(boundTarget)
  #expect(updatedTarget.isVisible)
}

@Test(arguments: [true, false, nil] as [Bool?])
func windowMetadataRequiresAnExplicitOnScreenFlag(_ onScreen: Bool?) throws {
  var entry = windowEntry(id: 1, frame: CGRect(x: 100, y: 100, width: 600, height: 400))
  entry[kCGWindowIsOnscreen as String] = onScreen
  let parsed = try #require(WindowServerSource.ParsedWindowEntry(dictionary: entry))
  #expect(parsed.isOnScreen == (onScreen == true))
  #expect(parsed.isVisible == (onScreen == true))
}

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

@Test @MainActor func companionHUDTracksTheCompanionLevelWithoutRecreatingItsWindow() throws {
  _ = NSApplication.shared
  let companion = NSPanel(
    contentRect: CGRect(x: 200, y: 600, width: 64, height: 64), styleMask: [.borderless],
    backing: .buffered, defer: false)
  companion.isReleasedWhenClosed = false
  defer { companion.close() }
  let hud = CompanionHUDController(appearance: ThemeEnvironment())
  defer { hud.close() }
  hud.companionWindow = companion
  let target = WindowTargetCandidate(
    windowID: 1, processID: 123, appName: "Meeting",
    frame: CGRect(x: 100, y: 100, width: 600, height: 400))
  let state = CompanionBindingState.active(target: target, skill: .listen, startedAt: 0)
  let levels: [NSWindow.Level] = [
    .normal, .floating, CompanionPanel.normalOverlayLevel,
    CompanionPanel.floatingOverlayLevel, .normal,
  ]
  var originalWindowNumber: Int?
  for level in levels {
    companion.level = level
    hud.prepare(
      state: state,
      anchor: .init(
        companionPoint: companion.frame.origin, characterSize: 64,
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)))
    let window = try #require(hud.windowNumber.flatMap { NSApp.window(withWindowNumber: $0) })
    #expect(window.level == level)
    #expect(!window.isVisible)
    #expect(!window.canBecomeKey && !window.canBecomeMain)
    if let originalWindowNumber {
      #expect(window.windowNumber == originalWindowNumber)
    } else {
      originalWindowNumber = window.windowNumber
    }
  }
  #expect(hud.layoutMeasurements == 1)
  #expect(hud.model.state == state)
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
    configuration: .init(
      definition: definition,
      size: 64,
      seed: 1),
    rig: CatRig(),
    transitions: TransitionLibrary(), appearance: ThemeEnvironment())
  defer { pet.closeAllPanels() }
  var target = WindowTargetCandidate(
    windowID: try #require(window.windowServerID),
    processID: ProcessInfo.processInfo.processIdentifier,
    appName: "Meeting", frame: window.frame)
  pet.updateBinding(.active(target: target, skill: .listen, startedAt: 0))
  pet.place(at: CGPoint(x: 400, y: window.frame.maxY + 1))
  pet.presentation.show(reducedMotion: true)
  pet.refreshHUD()
  #expect(pet.panel.level == .normal)
  #expect(pet.panel.isVisible)
  #expect(pet.hud.isVisible)
  let hudWindow = try #require(pet.hud.windowNumber.flatMap { NSApp.window(withWindowNumber: $0) })
  #expect(hudWindow.level == pet.panel.level)
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
  let stacking = AppContentWindowStacking()
  stacking.register(transcript)
  stacking.update(.foreground)
  #expect(transcript.level == CompanionPanel.contentWindowLevel)
  #expect(transcript.level.rawValue < pet.panel.level.rawValue)
  pet.endPickup()
  #expect(transcript.level.rawValue > pet.panel.level.rawValue)
  stacking.update(.background)
  #expect(transcript.level == .normal)
}

private func windowEntry(id: UInt32, frame: CGRect) -> [String: Any] {
  [
    kCGWindowNumber as String: id, kCGWindowOwnerPID as String: Int32(123),
    kCGWindowLayer as String: 0, kCGWindowIsOnscreen as String: true,
    kCGWindowAlpha as String: 1.0, kCGWindowBounds as String: frame.dictionaryRepresentation,
  ]
}
