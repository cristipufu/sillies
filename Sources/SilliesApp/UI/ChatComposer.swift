import AppKit
import SwiftUI

/// Native editing keeps input-method composition and standard selection/copy behavior intact.
struct ChatComposer: NSViewRepresentable {
  @Environment(\.silliesTheme) private var theme
  @Environment(\.chatReadingSize) private var readingSize
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.chatTextPresentation) private var presentation
  @Binding var text: String
  let isEditable: Bool
  let send: () -> Void
  var focusChanged: (Bool) -> Void = { _ in }
  var focusRequest: UUID? = nil
  static let textInset = CGSize(width: 8, height: 8)
  private static let minimumHeight: CGFloat = 48
  private static let maximumHeight: CGFloat = 128

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    let editor = ChatComposerTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 68))
    editor.delegate = context.coordinator
    editor.isRichText = false
    editor.drawsBackground = false
    editor.font = ChatTypography.messageFont
    editor.defaultParagraphStyle = ChatTypography.paragraphStyle
    editor.typingAttributes = ChatTypography.attributes
    TextEditorAppearance.apply(theme, to: editor)
    ChatTypography.apply(readingSize, to: editor)
    editor.textContainerInset = Self.textInset
    editor.textContainer?.lineFragmentPadding = 0
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
    ChatTypography.apply(readingSize, to: editor)
    if editor.string != text, !editor.hasMarkedText() { editor.string = text }
    editor.isEditable = isEditable && isEnabled
    NativeTextVisibility.apply(presentation, to: editor)
    editor.onSend = send
    editor.focusChanged = focusChanged
    context.coordinator.requestFocus(focusRequest, for: editor)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context)
    -> CGSize?
  {
    guard let width = proposal.width, let editor = scroll.documentView as? NSTextView,
      let measured = context.coordinator.measurement.size(
        of: editor.attributedString(), width: width - Self.textInset.width * 2)
    else { return nil }
    return CGSize(
      width: width,
      height: min(
        Self.maximumHeight, max(Self.minimumHeight, measured.height + Self.textInset.height * 2)))
  }
  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: ChatComposer
    let measurement = ChatTextLayout()
    private var focusRequest: UUID?
    init(_ parent: ChatComposer) { self.parent = parent }
    func requestFocus(_ request: UUID?, for editor: NSTextView) {
      guard let request, request != focusRequest else { return }
      focusRequest = request
      MainRunLoopDelivery.perform { [weak editor] in
        guard let editor, editor.isEditable, editor.window?.isVisible == true else { return }
        editor.window?.makeFirstResponder(editor)
      }
    }
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
  var focusChanged: ((Bool) -> Void)?
  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { focusChanged?(true) }
    return accepted
  }
  override func resignFirstResponder() -> Bool {
    let accepted = super.resignFirstResponder()
    if accepted { focusChanged?(false) }
    return accepted
  }
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
