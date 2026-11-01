import AppKit
import SwiftUI

/// Native editing keeps input-method composition and standard selection/copy behavior intact.
struct ChatComposer: NSViewRepresentable {
  @Environment(\.silliesTheme) private var theme
  @Binding var text: String
  let isEditable: Bool
  let send: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    let editor = ChatComposerTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 68))
    editor.delegate = context.coordinator
    editor.isRichText = false
    editor.drawsBackground = false
    editor.font = .systemFont(ofSize: 15)
    TextEditorAppearance.apply(theme, to: editor)
    editor.textContainerInset = CGSize(width: 4, height: 8)
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.autoresizingMask = [.width]
    editor.textContainer?.widthTracksTextView = true
    editor.setAccessibilityLabel(String(localized: "Message"))
    scroll.documentView = editor
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let editor = scroll.documentView as? ChatComposerTextView else { return }
    TextEditorAppearance.apply(theme, to: editor)
    if editor.string != text, !editor.hasMarkedText() { editor.string = text }
    editor.isEditable = isEditable
    editor.onSend = send
  }
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: ChatComposer
    init(_ parent: ChatComposer) { self.parent = parent }
    func textDidChange(_ notification: Notification) {
      guard let editor = notification.object as? NSTextView else { return }
      parent.text = editor.string
    }
  }
}

@MainActor final class ChatComposerTextView: NSTextView {
  private static let returnKey: UInt16 = 36
  private static let keypadReturnKey: UInt16 = 76
  var onSend: (() -> Void)?
  override func keyDown(with event: NSEvent) {
    let isReturn = event.keyCode == Self.returnKey || event.keyCode == Self.keypadReturnKey
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if isReturn, !hasMarkedText(), !modifiers.contains(.shift), !modifiers.contains(.option) {
      if isEditable, !event.isARepeat { onSend?() }
      return
    }
    super.keyDown(with: event)
  }
}
