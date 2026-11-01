import AppKit
import SilliesCore
import SwiftUI

/// Only the native outline moves when a clamped bubble's tail follows the mascot.
/// Drag samples never invalidate the hosted transcript or composer through SwiftUI state.
struct ConversationBubbleChrome: NSViewRepresentable {
  static let borderWidth: CGFloat = 1
  @Environment(\.silliesTheme) private var theme
  let presentation: ConversationBubblePresentation

  func makeNSView(context: Context) -> ConversationBubbleChromeView {
    let view = ConversationBubbleChromeView(theme: theme)
    presentation.onTailChanged = { [weak view] in view?.moveTail($0, to: $1) }
    return view
  }
  func updateNSView(_ view: ConversationBubbleChromeView, context: Context) {
    view.update(theme: theme, tail: presentation.tail, offset: presentation.tailOffset)
  }
}

@MainActor final class ConversationBubbleChromeView: NSView {
  private let outline = CAShapeLayer()
  private var theme: SilliesTheme
  private var tail = ConversationBubbleLayout.Tail.top
  private var offset: CGFloat = 0
  override var isFlipped: Bool { true }
  override var isOpaque: Bool { false }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  init(theme: SilliesTheme) {
    self.theme = theme
    super.init(frame: .zero)
    wantsLayer = true
    outline.lineWidth = ConversationBubbleChrome.borderWidth
    layer?.addSublayer(outline)
  }
  required init?(coder: NSCoder) { nil }
  override func layout() {
    super.layout()
    redraw()
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    redraw()
  }
  func update(theme: SilliesTheme, tail: ConversationBubbleLayout.Tail, offset: CGFloat) {
    self.theme = theme
    self.tail = tail
    self.offset = offset
    redraw()
  }
  func moveTail(_ tail: ConversationBubbleLayout.Tail, to offset: CGFloat) {
    guard self.offset != offset || self.tail != tail else { return }
    self.tail = tail
    self.offset = offset
    redraw()
  }
  private func redraw() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    outline.frame = bounds
    outline.path =
      ConversationBubbleOutline(
        tail: tail, offset: offset,
        inset: ConversationBubbleChrome.borderWidth / 2
      ).path(in: bounds)
    effectiveAppearance.performAsCurrentDrawingAppearance {
      outline.fillColor = theme.native(.paper).cgColor
      outline.strokeColor = theme.native(.border).cgColor
    }
    CATransaction.commit()
  }
}
