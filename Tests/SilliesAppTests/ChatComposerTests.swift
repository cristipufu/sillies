import AppKit
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func chatComposerExpandsForMultilineDraftsThenScrollsWithinABoundedHeight()
  async throws
{
  let session = ChatWindowFixture.makeSession()
  defer { session.finish {} }
  let host = NSHostingController(rootView: ChatComposerField(model: session))
  host.sizingOptions = []
  host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 160)
  let proposal = CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
  session.draft = "Hello."
  await Task.yield()
  let compact = host.sizeThatFits(in: proposal)
  session.draft = "First thought.\nA second thought.\nA third thought."
  await Task.yield()
  let expanded = host.sizeThatFits(in: proposal)
  let longDraft = String(repeating: "A long draft that still needs editing.\n", count: 100)
  session.draft = longDraft
  await Task.yield()
  let bounded = host.sizeThatFits(in: proposal)
  #expect(expanded.height > compact.height)
  #expect(bounded.height >= expanded.height && bounded.height < 160)
  #expect(bounded.width <= proposal.width)
  #expect(session.draft == longDraft)
}

@Test @MainActor func chatReturnSendsButShiftReturnAndInputCompositionDoNot() throws {
  let editor = ChatComposerTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 80))
  let window = NSWindow(
    contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = editor
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
