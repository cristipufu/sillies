import AppKit
import Carbon

/// The clipboard is restored only while this transaction still owns its change count.
actor ClipboardPasteTransaction: ClipboardPasting {
  private static let maximumPreservedBytes = 16 * 1_024 * 1_024
  private struct Item { let values: [(NSPasteboard.PasteboardType, Data)] }
  private var original: [Item] = []
  private var ownedChange: Int?
  private let name: NSPasteboard.Name

  init(name: NSPasteboard.Name = .general) { self.name = name }

  func prepare(_ text: String) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard ownedChange == nil else { throw TextAccessError.failed }
    try Task.checkCancellation()
    let pasteboard = NSPasteboard(name: name)
    let before = pasteboard.changeCount
    var bytes = 0
    var items: [Item] = []
    for item in pasteboard.pasteboardItems ?? [] {
      var values: [(NSPasteboard.PasteboardType, Data)] = []
      for type in item.types {
        guard let data = item.data(forType: type) else { throw TextAccessError.unsupported }
        bytes += data.count
        guard bytes <= Self.maximumPreservedBytes else { throw TextAccessError.unsupported }
        values.append((type, data))
      }
      items.append(Item(values: values))
    }
    guard pasteboard.changeCount == before else { throw TextAccessError.changed }
    original = items
    pasteboard.clearContents()
    let written = pasteboard.setString(text, forType: .string)
    ownedChange = pasteboard.changeCount
    guard written else { throw TextAccessError.failed }
  }

  func paste(to processID: Int32) throws {
    try Task.checkCancellation()
    guard let ownedChange, NSPasteboard(name: name).changeCount == ownedChange else {
      throw TextAccessError.changed
    }
    guard
      let down = CGEvent(
        keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
      let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
    else { throw TextAccessError.failed }
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.postToPid(processID)
    up.postToPid(processID)
  }

  @discardableResult func restore() -> Bool {
    let pasteboard = NSPasteboard(name: name)
    defer {
      ownedChange = nil
      original.removeAll()
    }
    guard let ownedChange, pasteboard.changeCount == ownedChange else { return true }
    // Construct representations before mutating the shared clipboard.
    var items: [NSPasteboardItem] = []
    for item in original {
      let restored = NSPasteboardItem()
      for (type, data) in item.values {
        guard restored.setData(data, forType: type) else {
          fputs("Could not reconstruct a clipboard representation after pasting.\n", stderr)
          return false
        }
      }
      items.append(restored)
    }
    guard pasteboard.changeCount == ownedChange else { return true }
    pasteboard.clearContents()
    if !items.isEmpty, !pasteboard.writeObjects(items) {
      fputs("Could not restore the clipboard after pasting.\n", stderr)
      return false
    }
    return true
  }
}
