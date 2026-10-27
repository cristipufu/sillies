import AppKit
import SilliesCore

enum CompanionMenuAction {
  case skill(CompanionSkillKind)
  case saveClipboard
  case openStash
  case openSession
}

@MainActor
private final class CompanionMenuTarget: NSObject {
  let perform: () -> Void
  init(_ perform: @escaping () -> Void) { self.perform = perform }
  @objc func invoke(_ sender: NSMenuItem) { perform() }
}

@MainActor
enum CompanionActionMenu {
  static func make(
    windowName: String?, hasAudioSession: Bool,
    perform: @escaping (CompanionMenuAction) -> Void
  ) -> NSMenu {
    let menu = NSMenu(title: "Companion skills")
    menu.autoenablesItems = false
    for skill in CompanionSkillKind.radialSkills {
      let item = add(skill.title, symbol: skill.symbolName, to: menu) { perform(.skill(skill)) }
      item.isEnabled = !skill.requiresWindow || windowName != nil
      item.toolTip =
        skill == .record
        ? "Record the microphone and save playable audio with notes."
        : "\(skill.title) · \(windowName ?? "Choose a window first")"
    }
    if hasAudioSession {
      add("Open current session", symbol: "waveform", to: menu) { perform(.openSession) }
    }
    menu.addItem(.separator())
    add("Save Clipboard to Pocket Stash", symbol: "clipboard", to: menu) { perform(.saveClipboard) }
    add("Open Pocket Stash…", symbol: "tray", to: menu) { perform(.openStash) }
    return menu
  }

  @discardableResult
  private static func add(
    _ title: String, symbol: String, to menu: NSMenu, perform: @escaping () -> Void
  ) -> NSMenuItem {
    let target = CompanionMenuTarget(perform)
    let item = NSMenuItem(
      title: title, action: #selector(CompanionMenuTarget.invoke(_:)), keyEquivalent: "")
    item.target = target
    item.representedObject = target
    item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    menu.addItem(item)
    return item
  }
}
