import AppKit

/// Native editing commands follow the focused view, including SwiftUI's selectable text.
@MainActor
enum ApplicationMenu {
  static func make() -> NSMenu {
    let menu = NSMenu()
    let application = NSMenu(title: "Sillies")
    application.addItem(
      withTitle: "Quit Sillies", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    append(application, to: menu)

    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    append(edit, to: menu)
    return menu
  }

  private static func append(_ submenu: NSMenu, to menu: NSMenu) {
    let item = NSMenuItem()
    item.title = submenu.title
    item.submenu = submenu
    menu.addItem(item)
  }
}
