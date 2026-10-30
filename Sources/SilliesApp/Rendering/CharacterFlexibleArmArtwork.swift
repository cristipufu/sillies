import AppKit
import QuartzCore

/// A continuous sleeve and rounded fingers, shared by tools and contact gestures.
@MainActor
final class CharacterFlexibleArmArtwork {
  private enum Geometry {
    static let shoulderHeight = 0.88
    static let outlineWidth = 12.0
    static let sleeveWidth = 9.0
    static let elbowDrop = 12.0
    static let handBounds = CGRect(x: -6.5, y: -5.5, width: 13, height: 11)
  }
  let outline = CAShapeLayer()
  let sleeve = CAShapeLayer()
  let hand = CALayer()
  private let shoulder: CGPoint

  init(source: CALayer, parent: CALayer, rig: CharacterRig) {
    shoulder = CGPoint(
      x: source.frame.midX, y: source.frame.minY + source.bounds.height * Geometry.shoulderHeight)
    for (part, width, color) in [
      (outline, Geometry.outlineWidth, rig.gripOutline),
      (sleeve, Geometry.sleeveWidth, rig.sleeveFill),
    ] {
      part.fillColor = nil
      part.strokeColor = NSColor(hex: color).cgColor
      part.lineWidth = width
      part.lineCap = .round
      parent.addSublayer(part)
    }
    hand.bounds = Geometry.handBounds
    CharacterHandArtwork.draw(on: hand, at: Geometry.handBounds.origin, rig: rig)
    parent.addSublayer(hand)
  }

  func path(to grip: CGPoint) -> CGPath {
    let path = CGMutablePath()
    path.move(to: shoulder)
    path.addQuadCurve(
      to: grip,
      control: CGPoint(
        x: (shoulder.x + grip.x) / 2, y: min(shoulder.y, grip.y) - Geometry.elbowDrop))
    return path
  }

  func pose(at grip: CGPoint, angle: CGFloat = 0) {
    outline.path = path(to: grip)
    sleeve.path = outline.path
    hand.position = grip
    hand.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
  }

  func reset() {
    for part in [outline, sleeve, hand] { part.removeAllAnimations() }
  }
}
