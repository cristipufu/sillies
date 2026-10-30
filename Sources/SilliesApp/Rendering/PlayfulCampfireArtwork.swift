import AppKit
import QuartzCore

/// A fixed, tiny flame rig: independent silhouettes, warm light, and four recycled embers.
@MainActor
final class PlayfulCampfireArtwork {
  private struct Flame {
    let layer: CAShapeLayer
    let width: CGFloat
    let height: CGFloat
  }
  static let templateSize = CGSize(width: 66, height: 76)
  let layer = CALayer()
  private let glow = CAGradientLayer()
  private var flames: [Flame] = []
  private var embers: [CALayer] = []
  private static let times: [NSNumber] = [0, 0.2, 0.4, 0.6, 0.8, 1]

  init() {
    layer.bounds = CGRect(origin: .zero, size: Self.templateSize)
    configureGlow()
    configureLogs()
    for (width, height, color) in [(22.0, 62.0, "E97F59"), (15, 49, "F7B75F"), (8, 34, "FFE9A4")] {
      let part = CAShapeLayer()
      part.fillColor = NSColor(hex: color).cgColor
      part.path = silhouette(width: width, height: height, bend: 0)
      layer.addSublayer(part)
      flames.append(Flame(layer: part, width: width, height: height))
    }
    for _ in 0..<4 {
      let ember = CALayer()
      ember.bounds = CGRect(x: 0, y: 0, width: 2, height: 3)
      ember.cornerRadius = 1
      ember.backgroundColor = NSColor(hex: "F9CF82").cgColor
      ember.opacity = 0
      layer.addSublayer(ember)
      embers.append(ember)
    }
  }

  func animate() {
    RigAnimation.swing(glow, "opacity", from: 0.45, to: 0.8, duration: 1.1)
    for (index, flame) in flames.enumerated() {
      let bends: [CGFloat] = [0, -3, 2, 5, -2, 0]
      let heights: [CGFloat] = [0, 4, -3, 2, 5, 0]
      let paths = bends.indices.map { sample in
        silhouette(width: flame.width, height: flame.height + heights[sample], bend: bends[sample])
      }
      let motion = CAKeyframeAnimation(keyPath: "path")
      motion.values = paths
      motion.keyTimes = Self.times
      motion.duration = 0.85 + Double(index) * 0.23
      motion.timeOffset = Double(index) * 0.31
      motion.repeatCount = .infinity
      motion.timingFunctions = bends.dropFirst().map { _ in
        CAMediaTimingFunction(name: .easeInEaseOut)
      }
      flame.layer.add(motion, forKey: "flame")
    }
    for (index, ember) in embers.enumerated() { animateEmber(ember, index: index) }
  }

  func stop() {
    glow.removeAllAnimations()
    for flame in flames { flame.layer.removeAllAnimations() }
    for ember in embers { ember.removeAllAnimations() }
  }

  private func configureGlow() {
    glow.frame = CGRect(x: 0, y: 4, width: 66, height: 62)
    glow.type = .radial
    glow.startPoint = CGPoint(x: 0.5, y: 0.4)
    glow.endPoint = CGPoint(x: 1, y: 1)
    glow.colors = [
      NSColor(hex: "F8C482", alpha: 0.35).cgColor, NSColor(hex: "F8C482", alpha: 0).cgColor,
    ]
    glow.opacity = 0.6
    layer.addSublayer(glow)
  }

  private func configureLogs() {
    for angle in [-0.23, 0.23] {
      let log = CALayer()
      log.bounds = CGRect(x: 0, y: 0, width: 48, height: 8)
      log.position = CGPoint(x: 33, y: 8)
      log.cornerRadius = 4
      log.backgroundColor = NSColor(hex: "896047").cgColor
      log.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
      layer.addSublayer(log)
      let grain = CALayer()
      grain.frame = CGRect(x: 8, y: 5, width: 31, height: 1)
      grain.backgroundColor = NSColor(hex: "BD9169").cgColor
      log.addSublayer(grain)
    }
  }

  private func silhouette(width: CGFloat, height: CGFloat, bend: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 33, y: 12))
    path.addCurve(
      to: CGPoint(x: 33 - width, y: 28), control1: CGPoint(x: 20, y: 10),
      control2: CGPoint(x: 33 - width - 5, y: 18))
    path.addCurve(
      to: CGPoint(x: 31 + bend, y: height), control1: CGPoint(x: 33 - width, y: 40),
      control2: CGPoint(x: 35 + bend, y: height - 15))
    path.addCurve(
      to: CGPoint(x: 33 + width, y: 27), control1: CGPoint(x: 31 + bend, y: height - 16),
      control2: CGPoint(x: 35 + width, y: 40))
    path.addCurve(
      to: CGPoint(x: 33, y: 12), control1: CGPoint(x: 35 + width, y: 16),
      control2: CGPoint(x: 42, y: 11))
    path.closeSubpath()
    return path
  }

  private func animateEmber(_ ember: CALayer, index: Int) {
    let x = 20.0 + Double(index) * 8
    let drift = index.isMultiple(of: 2) ? -5.0 : 5.0
    let rise = CAKeyframeAnimation(keyPath: "position")
    rise.values = [
      CGPoint(x: x, y: 26), CGPoint(x: x + drift, y: 48), CGPoint(x: x - drift, y: 73),
    ].map { NSValue(point: $0) }
    rise.keyTimes = [0, 0.5, 1]
    let fade = CAKeyframeAnimation(keyPath: "opacity")
    fade.values = [0, 0.8, 0.4, 0]
    fade.keyTimes = [0, 0.15, 0.65, 1]
    let flight = CAAnimationGroup()
    flight.duration = 1.4 + Double(index) * 0.19
    rise.duration = flight.duration
    fade.duration = flight.duration
    flight.animations = [rise, fade]
    flight.repeatCount = .infinity
    flight.timeOffset = Double(index) * 0.47
    ember.add(flight, forKey: "ember")
  }
}
