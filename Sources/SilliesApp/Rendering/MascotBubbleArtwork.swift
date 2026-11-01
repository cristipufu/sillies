import AppKit
import QuartzCore

/// Shared material and edge treatment for meeting suggestions and playful messages.
@MainActor
final class MascotBubbleArtwork {
  let layer = CALayer()
  private let shadow = CAShapeLayer()
  private let fill = CAGradientLayer()
  private let mask = CAShapeLayer()
  private let border = CAShapeLayer()

  init() {
    layer.addSublayer(shadow)
    layer.addSublayer(fill)
    layer.addSublayer(border)
    fill.mask = mask
    fill.startPoint = CGPoint(x: 0.3, y: 0)
    fill.endPoint = CGPoint(x: 0.7, y: 1)
    shadow.shadowRadius = 7
    shadow.shadowOffset = CGSize(width: 0, height: -2)
    shadow.shadowOpacity = 0.12
    shadow.shadowColor = NSColor(hex: "332940").cgColor
    border.fillColor = nil
    border.lineWidth = 1
  }

  func update(frame: CGRect, path: CGPath, appearance: NSAppearance) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.frame = frame
    fill.frame = layer.bounds
    mask.path = path
    shadow.path = path
    shadow.shadowPath = path
    border.path = path
    appearance.performAsCurrentDrawingAppearance {
      fill.colors = [SilliesTheme.native(.card).cgColor, SilliesTheme.native(.paper).cgColor]
      shadow.fillColor = SilliesTheme.native(.card).cgColor
      border.strokeColor = SilliesTheme.native(.border).cgColor
    }
    CATransaction.commit()
  }
}
