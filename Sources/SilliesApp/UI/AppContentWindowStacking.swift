import AppKit

/// Content takes priority over companion overlays while Sillies is active.
/// Native application activation drives updates; no window polling or animation work is needed.
@MainActor final class AppContentWindowStacking {
  enum Focus { case foreground, background }
  static let shared = AppContentWindowStacking()
  private struct Entry {
    weak var window: NSWindow?
    let backgroundLevel: NSWindow.Level
  }
  private var entries: [Entry] = []

  func register(_ window: NSWindow) {
    entries.removeAll { $0.window == nil }
    guard !entries.contains(where: { $0.window === window }) else { return }
    let entry = Entry(window: window, backgroundLevel: window.level)
    entries.append(entry)
    apply(NSApp.isActive ? .foreground : .background, to: entry)
  }

  func update(_ focus: Focus) {
    entries.removeAll { $0.window == nil }
    for entry in entries { apply(focus, to: entry) }
    if focus == .foreground, let key = NSApp.keyWindow,
      entries.contains(where: { $0.window === key })
    {
      key.orderFront(nil)
    }
  }

  private func apply(_ focus: Focus, to entry: Entry) {
    guard let window = entry.window else { return }
    let level = focus == .foreground ? CompanionPanel.contentWindowLevel : entry.backgroundLevel
    if window.level != level { window.level = level }
  }
}
