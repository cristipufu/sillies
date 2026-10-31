import AppKit

extension NSWindow {
  /// AppKit can expose temporary window numbers outside WindowServer's identifier range.
  var windowServerID: CGWindowID? {
    guard let id = CGWindowID(exactly: windowNumber), id != kCGNullWindowID else { return nil }
    return id
  }
}
