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
    let view = NSTextView()
    view.isEditable = false
    view.isSelectable = true
    view.drawsBackground = false
    view.isRichText = false
    view.textContainerInset = .zero
    view.textContainer?.lineFragmentPadding = 0
    view.font = .systemFont(ofSize: 15)
    view.delegate = context.coordinator
    return view
  }
  func updateNSView(_ view: NSTextView, context: Context) {
    context.coordinator.selectionChanged = selectionChanged
    if view.string != text { context.coordinator.replaceText(in: view, with: text) }
    context.coordinator.resetSelection(in: view, revision: selectionReset)
    TextEditorAppearance.apply(theme, to: view)
    view.textColor = color
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context)
    -> CGSize?
  {
    guard let width = proposal.width, width > 0,
      let container = view.textContainer, let layout = view.layoutManager
    else { return nil }
    container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
    layout.ensureLayout(for: container)
    let used = layout.usedRect(for: container)
    return CGSize(width: min(width, ceil(used.width)), height: max(20, ceil(used.height)))
  }
  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    var selectionChanged: (Bool) -> Void
    private var selectionRevision: UUID?
    init(_ selectionChanged: @escaping (Bool) -> Void) { self.selectionChanged = selectionChanged }
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
      view.textStorage?.replaceCharacters(
        in: NSRange(location: prefix, length: previous.length - prefix),
        with: next.substring(from: prefix))
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
