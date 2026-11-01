import AppKit

/// Native title bars and backgrounds follow the same palette as their hosted content.
@MainActor final class AppWindowAppearance {
  private struct Entry { weak var window: NSWindow? }
  private var entries: [Entry] = []
  func register(_ window: NSWindow, theme: SilliesTheme) {
    entries.removeAll { $0.window == nil }
    guard !entries.contains(where: { $0.window === window }) else { return }
    entries.append(.init(window: window))
    apply(theme, to: window)
  }
  func refresh(_ theme: SilliesTheme) {
    entries.removeAll { $0.window == nil }
    for entry in entries { if let window = entry.window { apply(theme, to: window) } }
  }
  private func apply(_ theme: SilliesTheme, to window: NSWindow) {
    window.backgroundColor = theme.native(.paper)
    window.titlebarAppearsTransparent = true
    window.contentView?.needsDisplay = true
  }
}
