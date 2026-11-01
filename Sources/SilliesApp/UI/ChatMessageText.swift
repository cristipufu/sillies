import AppKit
import SwiftUI

/// Bounded native message text reports selection so arriving replies cannot pull the reader away.
struct ChatMessageText: NSViewRepresentable {
  @Environment(\.silliesTheme) private var theme
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
    if view.string != text { view.string = text }
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
  final class Coordinator: NSObject, NSTextViewDelegate {
    var selectionChanged: (Bool) -> Void
    init(_ selectionChanged: @escaping (Bool) -> Void) { self.selectionChanged = selectionChanged }
    func textViewDidChangeSelection(_ notification: Notification) {
      guard let view = notification.object as? NSTextView else { return }
      selectionChanged(view.selectedRange().length > 0)
    }
  }
}
