import AppKit
import SilliesCore
import Testing

@testable import SilliesApp

@Test @MainActor func transcriptionWindowNeverBecomesAPerchOrDropTarget() async throws {
  _ = NSApplication.shared
  let document = NSWindow(
    contentRect: CGRect(x: 200, y: 200, width: 800, height: 500), styleMask: [.titled],
    backing: .buffered, defer: false)
  document.isReleasedWhenClosed = false
  document.orderFront(nil)
  defer { document.close() }
  let utility = CompanionUtilityWindow(
    contentRect: CGRect(x: 220, y: 220, width: 640, height: 760), styleMask: [.titled, .resizable],
    backing: .buffered, defer: false)
  utility.isReleasedWhenClosed = false
  utility.makeKeyAndOrderFront(nil)
  defer { utility.close() }
  let id = UInt32(utility.windowNumber)
  #expect(utility.canBecomeKey)
  #expect(!utility.canBecomeMain)
  #expect(WindowTrackingExclusions.shared.contains(id))
  let top = NSScreen.screens.first?.frame.maxY ?? 0
  let candidate = await WindowTargetMetadata.shared.candidate(for: id, primaryScreenTop: top)
  #expect(candidate == nil)
  let entries: [[String: Any]] = [utility, document].map { window in
    [
      kCGWindowNumber as String: UInt32(window.windowNumber),
      kCGWindowOwnerPID as String: ProcessInfo.processInfo.processIdentifier,
      kCGWindowLayer as String: WindowServerSource.normalWindowLayer,
      kCGWindowIsOnscreen as String: true,
      kCGWindowBounds as String: window.frame.dictionaryRepresentation,
    ]
  }
  let candidates = WindowServerSource.extractCandidates(
    from: entries, for: ProcessInfo.processInfo.processIdentifier, currentWindowID: id)
  #expect(candidates.map(\.id) == [UInt32(document.windowNumber)])
  #expect(WindowServerSource.extractInputWindowFrames(from: entries)[Int(id)] != nil)
  utility.close()
  #expect(WindowTrackingExclusions.shared.contains(id))
  #expect(
    WindowServerSource.extractCandidates(
      from: Array(entries.prefix(1)), for: ProcessInfo.processInfo.processIdentifier,
      currentWindowID: id
    ).isEmpty)
  utility.makeKeyAndOrderFront(nil)
  #expect(WindowTrackingExclusions.shared.contains(UInt32(utility.windowNumber)))
}

@Test @MainActor func utilityWindowNotificationsLeaveTheTrackedWindowUnchanged() {
  _ = NSApplication.shared
  let tracker = WorkspaceTracker(useAccessibility: false)
  tracker.start()
  defer { tracker.stop() }
  tracker.simulateApplicationSwitchInFlight(processID: ProcessInfo.processInfo.processIdentifier)
  let frame = CGRect(x: 100, y: 100, width: 900, height: 500)
  tracker.simulateTrackedWindow(frame, windowID: 987_654)
  let window = CompanionUtilityWindow(
    contentRect: frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer { window.close() }
  for notification in [
    NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification,
    NSWindow.didMoveNotification, NSWindow.didResizeNotification,
    NSWindow.willMiniaturizeNotification, NSWindow.willCloseNotification,
  ] {
    NotificationCenter.default.post(name: notification, object: window)
    #expect(tracker.windowID == 987_654)
    #expect(tracker.windowFrame == frame)
  }
}
