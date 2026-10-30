import AppKit

/// The static anchor paints into a cleared backing surface, with transparent space above the rope.
@MainActor
final class PlayfulRopeAnchorView: NSView {
  private static let ropeWidth = 3.0
  private let ropeColor = NSColor(hex: "B18B60").cgColor
  private var path: CGPath?
  override var isOpaque: Bool { false }

  func update(path: CGPath) {
    self.path = path
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.clear(dirtyRect)
    guard let path else { return }
    context.setStrokeColor(ropeColor)
    context.setLineWidth(Self.ropeWidth)
    context.setLineCap(.round)
    context.addPath(path)
    context.strokePath()
  }
}
