import AppKit

/// Closing or minimizing Settings releases preview devices even while its hosted view is retained.
@MainActor final class SettingsWindowLifecycle: NSObject, NSWindowDelegate {
  private let stop: () -> Void
  private let refresh: () -> Void
  init(stop: @escaping () -> Void, refresh: @escaping () -> Void) {
    self.stop = stop
    self.refresh = refresh
  }
  func windowWillClose(_ notification: Notification) { stop() }
  func windowDidMiniaturize(_ notification: Notification) { stop() }
  func windowDidBecomeKey(_ notification: Notification) { refresh() }
}
