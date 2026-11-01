import AppKit
import Testing

@testable import SilliesApp

@Test @MainActor func chatReturnSendsButShiftReturnAndInputCompositionDoNot() throws {
  let editor = ChatComposerTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 80))
  let window = NSWindow(
    contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = editor
  window.makeKeyAndOrderFront(nil)
  defer { window.close() }
  #expect(window.makeFirstResponder(editor))
  var sends = 0
  editor.onSend = { sends += 1 }
  editor.string = "Hello"
  editor.setSelectedRange(NSRange(location: 5, length: 0))
  func key(_ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers,
        timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r",
        charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
  }
  editor.keyDown(with: try key())
  #expect(sends == 1 && editor.string == "Hello")
  editor.keyDown(with: try key(.shift))
  #expect(sends == 1 && editor.string.contains("\n"))
  editor.setMarkedText(
    "你", selectedRange: NSRange(location: 1, length: 0),
    replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(editor.hasMarkedText())
  editor.keyDown(with: try key())
  #expect(sends == 1)
}
