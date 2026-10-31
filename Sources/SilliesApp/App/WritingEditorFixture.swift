import AppKit

/// Separate-process editor: AX setters for one's own process bypass IPC and violate AppKit isolation.
@MainActor final class WritingEditorFixture {
  private let window = NSWindow(
    contentRect: CGRect(x: 300, y: 250, width: 580, height: 260),
    styleMask: [.titled, .closable], backing: .buffered, defer: false)
  private let editor = NSTextView()
  private let output = DispatchQueue(label: "app.sillies.writing-fixture-output")
  private var input = Data()

  func start() {
    window.isReleasedWhenClosed = false
    window.title = "Sillies · Writing insertion fixture"
    editor.isRichText = false
    window.contentView = editor
    let menu = NSMenu()
    let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    edit.submenu = NSMenu(title: "Edit")
    edit.submenu?.addItem(
      withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    menu.addItem(edit)
    NSApp.mainMenu = menu
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(editor)
    NSApp.activate(ignoringOtherApps: true)
    FileHandle.standardInput.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      MainRunLoopDelivery.perform { self?.receive(data) }
    }
  }

  func stop() {
    FileHandle.standardInput.readabilityHandler = nil
    window.close()
  }

  private func receive(_ data: Data) {
    guard !data.isEmpty else {
      NSApp.terminate(nil)
      return
    }
    input.append(data)
    while let end = input.firstIndex(of: Self.newline) {
      let line = input.prefix(upTo: end)
      do {
        let message = try JSONDecoder().decode(WritingFixtureMessage.self, from: line)
        if let text = message.text { editor.string = text }
        if let caret = message.caret {
          editor.setSelectedRange(NSRange(location: caret, length: 0))
        }
        let reply = WritingFixtureMessage(
          text: editor.string, caret: editor.selectedRange().location)
        var encoded = try JSONEncoder().encode(reply)
        encoded.append(Self.newline)
        let response = encoded
        output.async { FileHandle.standardOutput.write(response) }
      } catch {
        fputs("Writing fixture protocol failed: \(error)\n", stderr)
        NSApp.terminate(nil)
      }
      input.removeSubrange(...end)
    }
  }
  private static let newline: UInt8 = 10
}
