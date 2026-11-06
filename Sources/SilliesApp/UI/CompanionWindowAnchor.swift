import AppKit

/// A native ordering snapshot supplied by the companion owner; never a window-list lookup.
struct CompanionWindowAnchor: Equatable {
  let windowID: UInt32?
  let level: NSWindow.Level
}

extension CompanionWindowAnchor {
  @MainActor init(window: NSWindow) {
    windowID = window.windowServerID
    level = window.level
  }

  @MainActor func orderAbove(_ window: NSWindow) {
    if let windowID, windowID != 0 {
      window.order(.above, relativeTo: Int(windowID))
    } else {
      window.orderFront(nil)
    }
  }
}
