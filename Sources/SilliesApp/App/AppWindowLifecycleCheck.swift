import AppKit

/// Exercises native activation and popover teardown through the same actions as the menu bar.
@MainActor enum AppWindowLifecycleCheck {
  struct Actions {
    let prepareControlCenter: () -> ControlCenter
    let openSettings: () -> NSWindow?
    let openVault: () -> NSWindow?
  }
  @MainActor struct ControlCenter {
    let button: NSStatusBarButton?
    let popover: NSPopover
    var isReady: Bool {
      guard let frame = button?.window?.frame else { return false }
      return frame.width > 0 && frame.height > 0
    }
  }
  private enum Limits {
    static let repetitions = 3
    static let transitionTimeout: TimeInterval = 2
    static let pollInterval: Duration = .milliseconds(20)
  }

  static func run(controller: CompanionController, actions: Actions) async {
    let previousApplication = NSWorkspace.shared.frontmostApplication
    let companionCount = controller.liveCount
    do {
      let controlCenter = actions.prepareControlCenter()
      try await waitUntil("menu-bar item layout") { controlCenter.isReady }
      try await waitUntil("companions visible") { controller.diagnostics.visibleCount > 0 }
      NSApp.activate(ignoringOtherApps: true)
      try await waitUntil("application activation") { NSApp.isActive }
      for repetition in 0..<Limits.repetitions {
        for openWindow in [actions.openSettings, actions.openVault] {
          controlCenter.button?.performClick(nil)
          let popover = controlCenter.popover
          try await waitUntil("control center opens") { popover.isShown }
          guard let window = openWindow() else { throw Failure("The app window was not created.") }
          try await waitUntil("\(window.title) opens and closes the control center") {
            window.isVisible && window.isKeyWindow && !popover.isShown
          }
          controller.tracker.refreshFocus()
          guard let id = window.windowServerID,
            WindowTrackingExclusions.excludesSurface(
              id, ownerPID: ProcessInfo.processInfo.processIdentifier),
            controller.tracker.windowID != id
          else { throw Failure("An app window became a companion perch.") }
          guard controller.liveCount == companionCount, controller.shouldRun,
            controller.diagnostics.visibleCount > 0
          else {
            throw Failure("Opening an app window stopped the companions.")
          }
          guard
            window.level.rawValue
              > CompanionPanel.hudLevel(forWindowLayer: NSWindow.Level.floating.rawValue).rawValue
          else { throw Failure("Companion overlays can cover the app window.") }
          if repetition == 0 {
            try await verifyApplicationSwitch(window: window, previous: previousApplication)
          }
          window.close()
          try await waitUntil("\(window.title) closes") { !window.isVisible }
        }
      }
      print(
        "APP WINDOW CHECK PASSED: menu popover → Settings/Vault, activation, close/reopen, own-window exclusion, foreground/background stacking"
      )
      previousApplication?.activate(options: [])
      NSApp.terminate(nil)
    } catch {
      previousApplication?.activate(options: [])
      fputs("APP WINDOW CHECK FAILED: \(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }

  private static func verifyApplicationSwitch(window: NSWindow, previous: NSRunningApplication?)
    async throws
  {
    guard let previous, !previous.isTerminated,
      previous.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else { return }
    guard previous.activate(options: []) else {
      throw Failure("Could not switch to the previous app.")
    }
    try await waitUntil("\(window.title) returns to normal stacking") {
      !NSApp.isActive && window.level == .normal
    }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    try await waitUntil("\(window.title) returns above companion overlays") {
      NSApp.isActive && window.isKeyWindow && window.level == CompanionPanel.contentWindowLevel
    }
  }

  private static func waitUntil(_ transition: String, condition: () -> Bool) async throws {
    let deadline = ProcessInfo.processInfo.systemUptime + Limits.transitionTimeout
    while !condition() {
      guard ProcessInfo.processInfo.systemUptime < deadline else {
        throw Failure("Timed out waiting for \(transition).")
      }
      try await Task.sleep(for: Limits.pollInterval)
    }
  }

  private struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
  }
}
