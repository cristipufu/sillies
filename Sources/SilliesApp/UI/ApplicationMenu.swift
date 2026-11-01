import AppKit

/// Native editing commands follow the focused view, including SwiftUI's selectable text.
@MainActor
enum ApplicationMenu {
  static func make() -> NSMenu {
    let menu = NSMenu()
    let application = NSMenu(title: String(localized: "Sillies"))
    application.addItem(
      withTitle: String(localized: "Quit Sillies"), action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    append(application, to: menu)

    let edit = NSMenu(title: String(localized: "Edit"))
    edit.addItem(
      withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
    let redo = edit.addItem(
      withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(.separator())
    edit.addItem(
      withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(
      withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(
      withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"
    )
    edit.addItem(
      withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)),
      keyEquivalent: "a")
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
