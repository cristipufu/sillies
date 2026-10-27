import AppKit
import QuartzCore

/// Reusable drawing primitives; each character owns its palette, anatomy, and layout.
extension CharacterRig {
  private static let cheekSize = CGSize(width: 10, height: 5)
  private static let smileDepthRatio: CGFloat = 0.35
  private static let smileStrokeWidth: CGFloat = 1.8

  func softLimb(_ layer: CALayer, frame: CGRect, fill: String) {
    layer.frame = frame
    pill(on: layer, layer.bounds, fill, stroke: gripOutline)
  }

  func cheeks(on layer: CALayer, centers: [CGPoint], color: String) {
    for center in centers {
      let size = Self.cheekSize
      oval(
        on: layer,
        CGRect(
          x: center.x - size.width / 2, y: center.y - size.height / 2,
          width: size.width, height: size.height), color)
    }
  }

  func smile(on layer: CALayer, center: CGPoint, width: CGFloat, color: String) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: center.x - width / 2, y: center.y))
    path.addQuadCurve(
      to: CGPoint(x: center.x + width / 2, y: center.y),
      control: CGPoint(x: center.x, y: center.y - width * Self.smileDepthRatio))
    shape(on: layer, path: path, fill: nil, stroke: color, lineWidth: Self.smileStrokeWidth)
  }
}
