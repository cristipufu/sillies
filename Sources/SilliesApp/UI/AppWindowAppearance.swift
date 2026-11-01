import AppKit

/// Native title bars and backgrounds follow the same palette as their hosted content.
@MainActor final class AppWindowAppearance {
  static let shared = AppWindowAppearance()
  private struct Entry { weak var window: NSWindow? }
  private var entries: [Entry] = []
  func register(_ window: NSWindow) {
    entries.removeAll { $0.window == nil }
    guard !entries.contains(where: { $0.window === window }) else { return }
    entries.append(.init(window: window))
    apply(to: window)
  }
  func refresh() {
    entries.removeAll { $0.window == nil }
    for entry in entries { if let window = entry.window { apply(to: window) } }
  }
  private func apply(to window: NSWindow) {
    window.backgroundColor = SilliesTheme.native(.paper)
    window.titlebarAppearsTransparent = true
    window.contentView?.needsDisplay = true
  }
}
