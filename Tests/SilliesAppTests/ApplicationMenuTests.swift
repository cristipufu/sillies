import AppKit
import Testing

@testable import SilliesApp

@Test @MainActor func commandCCopiesTheSelectionThroughTheNativeResponderChain() throws {
  _ = NSApplication.shared
  let previousApplication = NSWorkspace.shared.frontmostApplication
  let previousPolicy = NSApp.activationPolicy()
  NSApp.setActivationPolicy(.accessory)
  defer {
    NSApp.setActivationPolicy(previousPolicy)
    previousApplication?.activate(options: [])
  }
  let previousMenu = NSApp.mainMenu
  NSApp.mainMenu = ApplicationMenu.make()
  defer { NSApp.mainMenu = previousMenu }
  let text = CopyProbeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
  let window = NSWindow(
    contentRect: text.frame, styleMask: [.titled], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = text
  window.makeKeyAndOrderFront(nil)
  NSApp.activate(ignoringOtherApps: true)
  defer {
    window.close()
    text.clipboard.releaseGlobally()
  }
  text.isEditable = false
  text.isSelectable = true
  try DisplayFrameSequence.presentCreatedWindows()
  window.makeKeyAndOrderFront(nil)
  #expect(window.isKeyWindow)
  for content in [
    "Warning: Invalid audio data", "Transcript: Ștefan spune mulțumesc.",
    "Summary: Release on Friday",
  ] {
    text.string = content
    let selection = NSRange(location: 0, length: min(12, (content as NSString).length))
    text.setSelectedRange(selection)
    #expect(window.makeFirstResponder(text))
    #expect((NSApp.target(forAction: #selector(NSText.copy(_:))) as? NSResponder) === text)
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: "c",
        charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
    #expect(NSApp.mainMenu?.performKeyEquivalent(with: event) == true)
    #expect(
      text.clipboard.string(forType: .string) == (content as NSString).substring(with: selection))
    #expect(text.string == content)
  }
}

/// Exercise native copy serialization without touching the person's real clipboard.
@MainActor private final class CopyProbeTextView: NSTextView {
  let clipboard = NSPasteboard.withUniqueName()
  override func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType])
    -> Bool
  {
    clipboard.clearContents()
    return super.writeSelection(to: clipboard, types: types)
  }
}
