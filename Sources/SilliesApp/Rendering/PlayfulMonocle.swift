import AppKit
import QuartzCore

/// A real vector magnification of this character's eye, clipped by a glass lens.
@MainActor
final class PlayfulMonocle {
  private enum Design {
    static let diameter: CGFloat = 48
    static let magnification: CGFloat = 2.2
    static let rimWidth: CGFloat = 2.5
  }
  let layer = CALayer()

  init(rig: CharacterRig) {
    let shapes = rig.eyes.sublayers?.compactMap { $0 as? CAShapeLayer } ?? []
    let pupils = shapes.compactMap(\.path).map(\.boundingBoxOfPath).filter {
      $0.width * $0.height > 20
    }
    let firstEye = pupils.min { $0.minX < $1.minX }
    let center =
      firstEye.map { CGPoint(x: $0.midX, y: $0.midY) }
      ?? CGPoint(x: rig.head.bounds.midX, y: rig.head.bounds.midY)
    let diameter = Design.diameter
    layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
    layer.position = center
    layer.name = ArtworkHitTester.decorationName
    layer.backgroundColor = NSColor(hex: "E4F3EF").cgColor
    layer.cornerRadius = diameter / 2
    layer.borderColor = NSColor(hex: "B58D4C").cgColor
    layer.borderWidth = Design.rimWidth
    layer.masksToBounds = true
    var magnification = CGAffineTransform(translationX: diameter / 2, y: diameter / 2)
      .scaledBy(x: Design.magnification, y: Design.magnification)
      .translatedBy(x: -center.x, y: -center.y)
    for shape in shapes {
      let copy = CAShapeLayer()
      copy.path = shape.path?.copy(using: &magnification)
      copy.fillColor = shape.fillColor
      copy.strokeColor = shape.strokeColor
      copy.lineWidth = shape.lineWidth * Design.magnification
      layer.addSublayer(copy)
    }
    let gleam = CAShapeLayer()
    let arc = CGMutablePath()
    arc.addArc(
      center: CGPoint(x: diameter / 2, y: diameter / 2), radius: diameter / 2 - 6,
      startAngle: .pi * 0.3, endAngle: .pi * 0.85, clockwise: false)
    gleam.path = arc
    gleam.fillColor = nil
    gleam.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
    gleam.lineWidth = 3
    gleam.lineCap = .round
    layer.addSublayer(gleam)
    rig.head.addSublayer(layer)
    layer.opacity = 0
  }
}
