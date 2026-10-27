import AppKit
import QuartzCore
import SilliesCore

/// Small bubble artwork follows the anchor without changing SwiftUI content during window movement.
@MainActor
final class MeetingSpeechBubbleBackground: NSView {
  private static let borderWidth: CGFloat = 1
  private static let borderOpacity: CGFloat = 0.26
  private static let shadowOpacity: Float = 0.14
  private static let shadowRadius: CGFloat = 8
  private static let shadowOffset = CGSize(width: 0, height: 3)
  private let bubble = CAShapeLayer()
  private var tail: SuggestionBubbleLayout.Tail?
  private var tailOffset: CGFloat?
  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    bubble.lineWidth = Self.borderWidth
    bubble.shadowColor = NSColor.black.cgColor
    bubble.shadowOpacity = Self.shadowOpacity
    bubble.shadowRadius = Self.shadowRadius
    bubble.shadowOffset = Self.shadowOffset
    layer?.addSublayer(bubble)
    updateColors()
  }

  required init?(coder: NSCoder) { nil }

  func update(_ layout: SuggestionBubbleLayout) {
    guard tail != layout.tail || tailOffset != layout.tailOffset else { return }
    tail = layout.tail
    tailOffset = layout.tailOffset
    let inset = SuggestionBubbleLayout.shadowInset
    let rect = bounds.insetBy(dx: inset, dy: inset)
    let path = SpeechBubbleShape(tail: layout.tail, tailOffset: layout.tailOffset - inset)
      .path(in: CGRect(origin: .zero, size: rect.size)).cgPath
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    bubble.frame = rect
    bubble.path = path
    bubble.shadowPath = path
    CATransaction.commit()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  private func updateColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      bubble.fillColor = NSColor(SilliesTheme.card).cgColor
      bubble.strokeColor =
        NSColor(SilliesTheme.accent).withAlphaComponent(Self.borderOpacity).cgColor
    }
  }
}
