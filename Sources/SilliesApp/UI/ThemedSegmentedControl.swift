import AppKit

/// Theme-owned artwork with AppKit retaining selection, keyboard navigation and accessibility.
final class ThemedSegmentedControl: NSSegmentedControl {
  private var theme: SilliesTheme
  private static let cornerRadius: CGFloat = 6
  private static let selectionInset: CGFloat = 2
  private static let labelInset: CGFloat = 8
  private static let borderWidth: CGFloat = 0.5

  init(theme: SilliesTheme) {
    self.theme = theme
    super.init(frame: .zero)
    font = .systemFont(ofSize: NSFont.systemFontSize)
  }

  required init?(coder: NSCoder) { return nil }

  func applyTheme(_ theme: SilliesTheme) {
    guard self.theme != theme else { return }
    self.theme = theme
    needsDisplay = true
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard segmentCount > 0 else { return }
    drawTrack(in: bounds)
    let segmentWidth = bounds.width / CGFloat(segmentCount)
    for segment in 0..<segmentCount {
      let frame = NSRect(
        x: bounds.minX + CGFloat(segment) * segmentWidth, y: bounds.minY,
        width: segmentWidth, height: bounds.height)
      drawChoice(segment, in: frame)
    }
  }

  private func drawTrack(in frame: NSRect) {
    let path = roundedPath(in: frame.insetBy(dx: Self.borderWidth, dy: Self.borderWidth))
    theme.native(.soft).setFill()
    path.fill()
    theme.native(.border).setStroke()
    path.lineWidth = Self.borderWidth
    path.stroke()
  }

  private func drawChoice(_ segment: Int, in frame: NSRect) {
    let selected = isSelected(forSegment: segment)
    let enabled = isEnabled && isEnabled(forSegment: segment)
    if selected {
      theme.native(enabled ? .accentFill : .selection).setFill()
      roundedPath(in: frame.insetBy(dx: Self.selectionInset, dy: Self.selectionInset)).fill()
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingTail
    let label = NSAttributedString(
      string: label(forSegment: segment) ?? "",
      attributes: [
        .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
        .foregroundColor: theme.native(enabled ? (selected ? .onAccent : .ink) : .secondary),
        .paragraphStyle: paragraph,
      ])
    let height = label.size().height
    label.draw(
      in: NSRect(
        x: frame.minX + Self.labelInset, y: frame.midY - height / 2,
        width: max(0, frame.width - Self.labelInset * 2), height: height))
  }

  private func roundedPath(in frame: NSRect) -> NSBezierPath {
    NSBezierPath(roundedRect: frame, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
  }
}
