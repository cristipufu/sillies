import AppKit
import Testing

@testable import SilliesApp

@Test @MainActor func foregroundContentOccludesMascotsEvenWhenTheirPanelsOrderForward() throws {
  _ = NSApplication.shared
  let stacking = AppContentWindowStacking()
  let frame = CGRect(x: 260, y: 260, width: 360, height: 240)
  let content = NSWindow(
    contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
  content.isReleasedWhenClosed = false
  let overlay = SkillFloatingPanel(contentRect: frame, ignoresMouseEvents: false)
  overlay.backgroundColor = .systemPink
  overlay.isOpaque = true
  overlay.alphaValue = 1
  defer {
    overlay.close()
    content.close()
  }
  stacking.register(content)
  content.makeKeyAndOrderFront(nil)
  stacking.update(.foreground)
  content.orderFrontRegardless()
  try DisplayFrameSequence.presentCreatedWindows()
  let id = try #require(content.windowServerID)
  let point = CGPoint(x: frame.midX, y: frame.midY)
  for level in [
    CompanionPanel.normalOverlayLevel, CompanionPanel.floatingOverlayLevel,
    CompanionPanel.hudLevel(forWindowLayer: NSWindow.Level.floating.rawValue),
  ] {
    overlay.level = level
    overlay.orderFrontRegardless()
    try DisplayFrameSequence.presentCreatedWindows()
    #expect(content.level.rawValue > overlay.level.rawValue)
    #expect(NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0) == Int(id))
  }
  #expect(content.canBecomeMain)
  #expect(content.canBecomeKey)
  #expect(
    WindowTrackingExclusions.excludesSurface(
      id, ownerPID: ProcessInfo.processInfo.processIdentifier))
}

@Test @MainActor func contentRestoresItsNativeLevelWhenSilliesDeactivates() {
  _ = NSApplication.shared
  let stacking = AppContentWindowStacking()
  let content = NSWindow(
    contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
  let panel = NSPanel(
    contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
  content.isReleasedWhenClosed = false
  panel.isReleasedWhenClosed = false
  panel.level = .floating
  defer {
    content.close()
    panel.close()
  }
  stacking.register(content)
  stacking.register(panel)
  for _ in 0..<20 {
    stacking.update(.foreground)
    #expect(content.level == CompanionPanel.contentWindowLevel)
    #expect(panel.level == CompanionPanel.contentWindowLevel)
    stacking.register(content)
    stacking.update(.background)
    #expect(content.level == .normal)
    #expect(panel.level == .floating)
  }
  weak var released: NSWindow?
  autoreleasepool {
    let temporary = NSWindow()
    temporary.isReleasedWhenClosed = false
    released = temporary
    stacking.register(temporary)
    temporary.close()
  }
  #expect(released == nil)
  stacking.update(.foreground)
}
