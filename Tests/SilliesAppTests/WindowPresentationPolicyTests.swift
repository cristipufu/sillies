import AppKit
import Testing

@testable import SilliesApp

@Test @MainActor func anchoredContentUsesTheActualMascotLevelAcrossActivationChanges() {
  let stacking = AppContentWindowStacking()
  let window = NSWindow(
    contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer { window.close() }
  stacking.register(window)
  for level in [
    NSWindow.Level.normal, CompanionPanel.normalOverlayLevel, .floating,
    CompanionPanel.floatingOverlayLevel,
  ] {
    stacking.update(.background)
    stacking.setCompanionAnchor(.init(windowID: nil, level: level), for: window)
    #expect(window.level == level)
    stacking.update(.foreground)
    #expect(
      window.level.rawValue == max(level.rawValue, CompanionPanel.contentWindowLevel.rawValue))
    stacking.update(.background)
    #expect(window.level == level)
    #expect(!window.isVisible)
  }
}

@Test @MainActor func audioDetailsUseOrdinaryWindowStackingWithoutOwningCapture() throws {
  let stacking = AppContentWindowStacking.shared
  defer { stacking.update(NSApp.isActive ? .foreground : .background) }
  stacking.update(.background)
  let controller = AudioSessionWindowController(appearance: ThemeEnvironment(), openTextModels: {})
  let session = AudioSessionPresentation(kind: .listen, sourceLabel: "Meeting")
  session.phase = .capturing
  var finished = false
  session.onFinish = { finished = true }
  controller.prepare(session)
  let window = try #require(controller.window)
  #expect(window.level == .normal)
  #expect(!window.isVisible)
  stacking.update(.foreground)
  #expect(window.level == CompanionPanel.contentWindowLevel)
  #expect(window.level.rawValue < NSWindow.Level.floating.rawValue)
  stacking.update(.background)
  #expect(window.level == .normal)
  controller.close()
  #expect(!finished)
  #expect(session.phase == .capturing)
}
