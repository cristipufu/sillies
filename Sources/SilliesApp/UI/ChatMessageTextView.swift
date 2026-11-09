import AppKit

/// SwiftUI owns the frame. Native text layout follows that committed width without resizing it.
@MainActor final class ChatMessageTextView: NSTextView {
  init() {
    let container = NSTextContainer()
    let layout = NSLayoutManager()
    let storage = NSTextStorage()
    layout.addTextContainer(container)
    storage.addLayoutManager(layout)
    super.init(frame: .zero, textContainer: container)
    isEditable = false
    isSelectable = true
    drawsBackground = false
    isRichText = true
    isVerticallyResizable = false
    isHorizontallyResizable = false
    textContainerInset = .zero
    container.lineFragmentPadding = 0
    container.widthTracksTextView = true
    container.heightTracksTextView = false
    font = ChatTypography.messageFont
    defaultParagraphStyle = ChatTypography.paragraphStyle
    typingAttributes = ChatTypography.attributes
  }
  required init?(coder: NSCoder) { nil }
}
