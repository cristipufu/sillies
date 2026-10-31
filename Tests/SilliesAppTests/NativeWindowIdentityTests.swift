import AppKit
import Testing

@testable import SilliesApp

@MainActor private final class WindowNumberFixture: NSWindow {
  var reportedNumber: Int?
  override var windowNumber: Int { reportedNumber ?? super.windowNumber }
}

@Test(arguments: [-1, 0, Int(UInt32.max) + 1, Int.max])
@MainActor func invalidNativeWindowNumbersNeverCrashFocusOrWindowNotifications(_ number: Int) {
  _ = NSApplication.shared
  let focus = WorkspaceFocusSession()
  let external = WorkspaceFocusSession.Application(
    processID: 999_999, name: "Editor", bundleIdentifier: "test.editor")
  focus.follow(external, continuity: .noPreviousWindow)
  let tracker = WorkspaceTracker(accessibility: .disabled)
  tracker.start()
  defer { tracker.stop() }
  tracker.simulateApplicationSwitchInFlight(processID: ProcessInfo.processInfo.processIdentifier)
  let frame = CGRect(x: 100, y: 100, width: 800, height: 500)
  tracker.simulateTrackedWindow(frame, windowID: 987_654)
  let window = WindowNumberFixture(
    contentRect: frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.orderFrontRegardless()
  window.reportedNumber = number
  defer {
    window.reportedNumber = nil
    window.close()
  }
  #expect(window.windowServerID == nil)
  #expect(focus.frontmostReplacement(for: .reconcileCurrent, application: .current) == nil)
  #expect(focus.application == external)
  for name in [
    NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification,
    NSWindow.didMoveNotification, NSWindow.didResizeNotification,
    NSWindow.willMiniaturizeNotification, NSWindow.willCloseNotification,
  ] {
    NotificationCenter.default.post(name: name, object: window)
    #expect(tracker.windowID == 987_654)
    #expect(tracker.windowFrame == frame)
  }
}

@Test(arguments: [1, Int(UInt32.max)])
@MainActor func nativeWindowIdentityPreservesValidBoundaryValues(_ number: Int) {
  _ = NSApplication.shared
  let window = WindowNumberFixture()
  window.isReleasedWhenClosed = false
  window.reportedNumber = number
  #expect(window.windowServerID == UInt32(exactly: number))
  window.reportedNumber = nil
  window.close()
}
