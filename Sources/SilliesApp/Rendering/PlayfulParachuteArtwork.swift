import AppKit
import QuartzCore
import SilliesCore

/// Canopy banking and suspension lines share one sampled compositor animation.
@MainActor
final class PlayfulParachuteArtwork {
  private static let sampleCount = 64
  private static let suspensionHeight = 70.0
  private static let pivot = CGPoint(x: 45, y: 68)
  let layer = CALayer()
  private let sail = CALayer()
  private let strings = CAShapeLayer()

  init() {
    let size = PlayfulPropLayout.parachuteTemplateSize
    sail.bounds = CGRect(origin: .zero, size: size)
    sail.anchorPoint = CGPoint(x: Self.pivot.x / size.width, y: Self.pivot.y / size.height)
    sail.position = Self.pivot
    layer.addSublayer(sail)
    configureCanopy()
  }

  func animate(_ motion: PlayfulSceneMotion, duration: Double) {
    let progress = (0...Self.sampleCount).map { Double($0) / Double(Self.sampleCount) }
    let angles = progress.map { motion.bankAngle(at: $0) }
    let tilt = CAKeyframeAnimation(keyPath: "transform.rotation.z")
    tilt.values = angles
    tilt.keyTimes = progress.map { NSNumber(value: $0) }
    tilt.duration = duration
    sail.add(tilt, forKey: "bank")
    let lines = CAKeyframeAnimation(keyPath: "path")
    lines.values = angles.map { suspensionLines(angle: $0) }
    lines.keyTimes = tilt.keyTimes
    lines.duration = duration
    strings.add(lines, forKey: "suspension")
  }

  func stop() {
    sail.removeAllAnimations()
    strings.removeAllAnimations()
  }

  private func suspensionLines(angle: Double) -> CGPath {
    let path = CGMutablePath()
    for x in [5.0, 28, 62, 85] {
      let dx = x - Self.pivot.x
      let dy = Self.suspensionHeight - Self.pivot.y
      path.move(
        to: CGPoint(
          x: Self.pivot.x + dx * cos(angle) - dy * sin(angle),
          y: Self.pivot.y + dx * sin(angle) + dy * cos(angle)))
      let grip =
        x < Self.pivot.x
        ? PlayfulPropLayout.parachuteLeftGrip : PlayfulPropLayout.parachuteRightGrip
      path.addLine(to: PlayfulPropLayout.parachuteStringAnchor(for: grip))
    }
    return path
  }

  private func configureCanopy() {
    let canopy = CAShapeLayer()
    let canopyPath = CGMutablePath()
    canopyPath.move(to: CGPoint(x: 3, y: 68))
    canopyPath.addCurve(
      to: CGPoint(x: 87, y: 68), control1: CGPoint(x: 12, y: 124), control2: CGPoint(x: 78, y: 124))
    canopyPath.addQuadCurve(to: CGPoint(x: 3, y: 68), control: CGPoint(x: 45, y: 83))
    canopy.path = canopyPath
    canopy.fillColor = NSColor(hex: "EDADAA").cgColor
    canopy.strokeColor = NSColor(hex: "B86E86").cgColor
    canopy.lineWidth = 2
    sail.addSublayer(canopy)
    let centerPanel = CAShapeLayer()
    let panelPath = CGMutablePath()
    panelPath.move(to: CGPoint(x: 28, y: 73))
    panelPath.addCurve(
      to: CGPoint(x: 45, y: 110), control1: CGPoint(x: 27, y: 96), control2: CGPoint(x: 35, y: 110))
    panelPath.addCurve(
      to: CGPoint(x: 62, y: 73), control1: CGPoint(x: 55, y: 110), control2: CGPoint(x: 63, y: 96))
    panelPath.addQuadCurve(to: CGPoint(x: 28, y: 73), control: CGPoint(x: 45, y: 78))
    centerPanel.path = panelPath
    centerPanel.fillColor = NSColor(hex: "F9D7C5").cgColor
    centerPanel.strokeColor = NSColor(hex: "C48291").cgColor
    centerPanel.lineWidth = 0.7
    sail.addSublayer(centerPanel)
    strings.path = suspensionLines(angle: 0)
    strings.strokeColor = NSColor(hex: "A39AAF").cgColor
    strings.fillColor = nil
    strings.lineWidth = 1
    layer.addSublayer(strings)
  }
}
