import AppKit
import QuartzCore
import SilliesCore

/// Small bubble artwork follows the anchor without changing SwiftUI content during window movement.
@MainActor
final class CompanionSpeechBubbleBackground: NSView {
  private let artwork = MascotBubbleArtwork()
  private var tail: CompanionSpeechBubbleLayout.Tail?
  private var tailOffset: CGFloat?
  private var appliedSize: CGSize?
  private var theme = SilliesTheme()
  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.addSublayer(artwork.layer)
    updateColors()
  }

  required init?(coder: NSCoder) { nil }

  func concealArtwork() { artwork.layer.isHidden = true }

  func update(_ layout: CompanionSpeechBubbleLayout) {
    artwork.layer.isHidden = false
    guard
      tail != layout.tail || tailOffset != layout.tailOffset || appliedSize != bounds.size
    else { return }
    tail = layout.tail
    tailOffset = layout.tailOffset
    appliedSize = bounds.size
    updateColors()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  func applyTheme(_ theme: SilliesTheme) {
    self.theme = theme
    updateColors()
  }

  private func updateColors() {
    guard let tail, let tailOffset else { return }
    let inset = CompanionSpeechBubbleLayout.shadowInset
    let rect = bounds.insetBy(dx: inset, dy: inset)
    let path = MascotBubbleContour.path(
      in: CGRect(origin: .zero, size: rect.size), tail: tail == .left ? .left : .right,
      offset: tailOffset - inset, depth: CompanionSpeechBubbleLayout.tailDepth)
    artwork.update(frame: rect, path: path, appearance: effectiveAppearance, theme: theme)
  }
}
