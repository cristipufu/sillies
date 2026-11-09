import AppKit
import SwiftUI

extension EnvironmentValues {
  @Entry var chatSelectionReset: UUID? = nil
}

/// Bounded native message text reports selection so arriving replies cannot pull the reader away.
struct ChatMessageText: NSViewRepresentable {
  @Environment(\.silliesTheme) private var theme
  @Environment(\.chatSelectionReset) private var selectionReset
  @Environment(\.chatReadingSize) private var readingSize
  @Environment(\.chatTextPresentation) private var presentation
  let text: String
  let color: NSColor
  let selectionChanged: (Bool) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(selectionChanged) }
  func makeNSView(context: Context) -> NSTextView {
    let view = ChatMessageTextView()
    view.delegate = context.coordinator
    return view
  }
  func updateNSView(_ view: NSTextView, context: Context) {
    context.coordinator.selectionChanged = selectionChanged
    NativeTextVisibility.apply(presentation, to: view)
    context.coordinator.applyAppearance(theme, color: color, to: view)
    context.coordinator.updateText(
      in: view, text: text,
      style: .init(size: readingSize.points, ink: color, codeBackground: theme.native(.card)))
    context.coordinator.resetSelection(in: view, revision: selectionReset)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context)
    -> CGSize?
  {
    guard let width = proposal.width else { return nil }
    return context.coordinator.measurement.size(of: view.attributedString(), width: width)
  }
  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    var selectionChanged: (Bool) -> Void
    let measurement = ChatTextLayout()
    private var selectionRevision: UUID?
    private var appliedTheme: SilliesTheme?
    private var appliedColor: NSColor?
    private var source: String?
    private var document: ChatMarkdownText?
    private var style: ChatMarkdownText.Style?
    init(_ selectionChanged: @escaping (Bool) -> Void) { self.selectionChanged = selectionChanged }
    func applyAppearance(_ theme: SilliesTheme, color: NSColor, to view: NSTextView) {
      guard appliedTheme != theme || appliedColor != color else { return }
      appliedTheme = theme
      appliedColor = color
      TextEditorAppearance.apply(theme, to: view)
      view.textColor = color
      view.linkTextAttributes = [
        .foregroundColor: theme.native(.accent), .underlineStyle: NSUnderlineStyle.single.rawValue,
      ]
    }
    func resetSelection(in view: NSTextView, revision: UUID?) {
      guard selectionRevision != revision else { return }
      selectionRevision = revision
      view.setSelectedRange(NSRange(location: 0, length: 0))
      selectionChanged(false)
    }
    func updateText(in view: NSTextView, text: String, style: ChatMarkdownText.Style) {
      guard !view.hasMarkedText(), source != text || self.style != style else { return }
      if source != text {
        source = text
        document = ChatMarkdownText(text)
      }
      self.style = style
      guard let document else { return }
      replaceText(in: view, with: document.render(style: style))
    }
    func replaceText(in view: NSTextView, with text: NSAttributedString) {
      guard let storage = view.textStorage else { return }
      let change = ChatTextReplacement(previous: view.string, next: text.string)
      let selections = view.selectedRanges
      storage.beginEditing()
      if change.previousRange.length > 0 || change.nextRange.length > 0 {
        storage.replaceCharacters(
          in: change.previousRange, with: text.attributedSubstring(from: change.nextRange))
      }
      text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) {
        attributes, range, _ in
        storage.setAttributes(attributes, range: range)
      }
      storage.endEditing()
      view.selectedRanges = selections.map {
        NSValue(range: change.selection($0.rangeValue))
      }
    }
    func textViewDidChangeSelection(_ notification: Notification) {
      guard let view = notification.object as? NSTextView else { return }
      selectionChanged(view.selectedRange().length > 0)
    }
  }
}
