import AppKit

/// Content takes priority over companion overlays while Sillies is active.
/// Native application activation drives updates; no window polling or animation work is needed.
@MainActor final class AppContentWindowStacking {
  enum Focus { case foreground, background }
  static let shared = AppContentWindowStacking()
  private enum Background: Equatable {
    case native(NSWindow.Level)
    case companion(CompanionWindowAnchor)
    var level: NSWindow.Level {
      switch self {
      case .native(let level): level
      case .companion(let anchor): anchor.level
      }
    }
  }
  private struct Entry {
    weak var window: NSWindow?
    var background: Background
  }
  private var entries: [Entry] = []
  private var focus: Focus?
  private var currentFocus: Focus { focus ?? (NSApp.isActive ? .foreground : .background) }

  func register(_ window: NSWindow) {
    entries.removeAll { $0.window == nil }
    guard !entries.contains(where: { $0.window === window }) else { return }
    let entry = Entry(window: window, background: .native(window.level))
    entries.append(entry)
    apply(currentFocus, to: entry)
  }

  func update(_ focus: Focus) {
    self.focus = focus
    entries.removeAll { $0.window == nil }
    for entry in entries { apply(focus, to: entry) }
    if focus == .foreground, let key = NSApp.keyWindow,
      entries.contains(where: { $0.window === key })
    {
      key.orderFront(nil)
    }
  }

  /// Anchored content occludes with the actual mascot, including bound normal-level panels.
  func setCompanionAnchor(_ anchor: CompanionWindowAnchor, for window: NSWindow) {
    guard let index = entries.firstIndex(where: { $0.window === window }),
      entries[index].background != .companion(anchor)
    else { return }
    entries[index].background = .companion(anchor)
    apply(currentFocus, to: entries[index])
  }

  private func apply(_ focus: Focus, to entry: Entry) {
    guard let window = entry.window else { return }
    let backgroundLevel = entry.background.level
    let level =
      focus == .foreground
      ? NSWindow.Level(
        rawValue: max(CompanionPanel.contentWindowLevel.rawValue, backgroundLevel.rawValue))
      : backgroundLevel
    if window.level != level { window.level = level }
    if focus == .background, window.isVisible, case .companion(let anchor) = entry.background {
      anchor.orderAbove(window)
    }
  }
}
