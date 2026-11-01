import AppKit

/// Native title bars and backgrounds follow the same palette as their hosted content.
@MainActor final class AppWindowAppearance {
  enum Background { case paper, transparent }
  private struct Entry {
    weak var window: NSWindow?
    let background: Background
  }
  private var entries: [Entry] = []
  func register(_ window: NSWindow, theme: SilliesTheme, background: Background) {
    entries.removeAll { $0.window == nil || $0.window === window }
    let entry = Entry(window: window, background: background)
    entries.append(entry)
    apply(theme, to: entry)
  }
  func refresh(_ theme: SilliesTheme) {
    entries.removeAll { $0.window == nil }
    for entry in entries { apply(theme, to: entry) }
  }
  private func apply(_ theme: SilliesTheme, to entry: Entry) {
    guard let window = entry.window else { return }
    window.backgroundColor = entry.background == .transparent ? .clear : theme.native(.paper)
    window.titlebarAppearsTransparent = true
    window.contentView?.needsDisplay = true
  }
}
