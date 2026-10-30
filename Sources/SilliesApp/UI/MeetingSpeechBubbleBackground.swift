import AppKit
import QuartzCore
import SilliesCore

/// Small bubble artwork follows the anchor without changing SwiftUI content during window movement.
@MainActor
final class MeetingSpeechBubbleBackground: NSView {
  private let artwork = MascotBubbleArtwork()
  private var tail: SuggestionBubbleLayout.Tail?
  private var tailOffset: CGFloat?
  private var appliedSize: CGSize?
  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.addSublayer(artwork.layer)
    updateColors()
  }

  required init?(coder: NSCoder) { nil }

  func update(_ layout: SuggestionBubbleLayout) {
    guard tail != layout.tail || tailOffset != layout.tailOffset || appliedSize != bounds.size
    else { return }
    tail = layout.tail
    tailOffset = layout.tailOffset
    appliedSize = bounds.size
    let inset = SuggestionBubbleLayout.shadowInset
    let rect = bounds.insetBy(dx: inset, dy: inset)
    let path = SpeechBubbleShape(tail: layout.tail, tailOffset: layout.tailOffset - inset)
      .path(in: CGRect(origin: .zero, size: rect.size)).cgPath
    artwork.update(frame: rect, path: path, appearance: effectiveAppearance)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  private func updateColors() {
    guard let tail, let tailOffset else { return }
    let inset = SuggestionBubbleLayout.shadowInset
    let rect = bounds.insetBy(dx: inset, dy: inset)
    let path = SpeechBubbleShape(tail: tail, tailOffset: tailOffset - inset)
      .path(in: CGRect(origin: .zero, size: rect.size)).cgPath
    artwork.update(frame: rect, path: path, appearance: effectiveAppearance)
  }
}
