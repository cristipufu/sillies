import AppKit
import SwiftUI

extension EnvironmentValues {
  @Entry var chatSelectionReset: UUID? = nil
}

/// Bounded native message text reports selection so arriving replies cannot pull the reader away.
struct ChatMessageText: NSViewRepresentable {
  @Environment(\.silliesTheme) private var theme
  @Environment(\.chatSelectionReset) private var selectionReset
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
    if view.string != text { context.coordinator.replaceText(in: view, with: text) }
    context.coordinator.resetSelection(in: view, revision: selectionReset)
    context.coordinator.applyAppearance(theme, color: color, to: view)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context)
    -> CGSize?
  {
    guard let width = proposal.width else { return nil }
    return context.coordinator.measurement.size(of: view.attributedString(), width: width)
  }
  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    var selectionChanged: (Bool) -> Void
    let measurement = ChatMessageLayout()
    private var selectionRevision: UUID?
    private var appliedTheme: SilliesTheme?
    private var appliedColor: NSColor?
    init(_ selectionChanged: @escaping (Bool) -> Void) { self.selectionChanged = selectionChanged }
    func applyAppearance(_ theme: SilliesTheme, color: NSColor, to view: NSTextView) {
      guard appliedTheme != theme || appliedColor != color else { return }
      appliedTheme = theme
      appliedColor = color
      TextEditorAppearance.apply(theme, to: view)
      view.textColor = color
    }
    func resetSelection(in view: NSTextView, revision: UUID?) {
      guard selectionRevision != revision else { return }
      selectionRevision = revision
      view.setSelectedRange(NSRange(location: 0, length: 0))
      selectionChanged(false)
    }
    func replaceText(in view: NSTextView, with text: String) {
      let previous = view.string as NSString
      let next = text as NSString
      let selections = view.selectedRanges
      var prefix = 0
      while prefix < min(previous.length, next.length),
        previous.character(at: prefix) == next.character(at: prefix)
      {
        prefix += 1
      }
      if prefix < previous.length {
        prefix = min(prefix, previous.rangeOfComposedCharacterSequence(at: prefix).location)
      }
      if prefix < next.length {
        prefix = min(prefix, next.rangeOfComposedCharacterSequence(at: prefix).location)
      }
      var attributes = ChatTypography.attributes
      if let color = view.textColor { attributes[.foregroundColor] = color }
      view.textStorage?.replaceCharacters(
        in: NSRange(location: prefix, length: previous.length - prefix),
        with: NSAttributedString(string: next.substring(from: prefix), attributes: attributes))
      view.selectedRanges = selections.map {
        let range = $0.rangeValue
        let location = min(range.location, next.length)
        return NSValue(
          range: NSRange(location: location, length: min(range.length, next.length - location)))
      }
    }
    func textViewDidChangeSelection(_ notification: Notification) {
      guard let view = notification.object as? NSTextView else { return }
      selectionChanged(view.selectedRange().length > 0)
    }
  }
}
