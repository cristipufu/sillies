import AppKit
import QuartzCore
import SilliesCore

@MainActor
final class PlayfulSharedArtwork {
  let root = CALayer()
  private let rope = CAShapeLayer()
  private let fire = PlayfulCampfireArtwork()
  private let plane = CAShapeLayer()
  private let parachute = PlayfulParachuteArtwork()
  private var lastSize = CGSize.zero

  init() {
    root.addSublayer(rope)
    root.addSublayer(fire.layer)
    root.addSublayer(plane)
    root.addSublayer(parachute.layer)
    rope.strokeColor = NSColor(hex: "B18B60").cgColor
    rope.fillColor = nil
    rope.lineWidth = 3
    rope.lineCap = .round
    configurePlane()
    hide()
  }

  func prepare(_ prop: PlayfulSceneDefinition.Prop, reducedMotion: Bool) {
    hide()
    rope.isHidden = prop != .rope
    fire.layer.isHidden = prop != .campfire
    plane.isHidden = prop != .plane
    parachute.layer.isHidden = prop != .parachute
    guard !reducedMotion else { return }
    if prop == .campfire {
      fire.animate()
    }
  }

  func animateParachute(_ motion: PlayfulSceneMotion, duration: Double) {
    parachute.animate(motion, duration: duration)
  }

  func facePlane(right: Bool) {
    plane.transform = CATransform3DMakeScale(right ? 1 : -1, 1, 1)
  }

  func resize(to size: CGSize) {
    guard size != lastSize else { return }
    lastSize = size
    root.frame = CGRect(origin: .zero, size: size)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 12, y: size.height / 2))
    path.addQuadCurve(
      to: CGPoint(x: size.width - 12, y: size.height / 2),
      control: CGPoint(x: size.width / 2, y: size.height / 2 - 5))
    rope.path = path
    let fireTemplate = PlayfulCampfireArtwork.templateSize
    let fireScale = min(size.width / fireTemplate.width, size.height / fireTemplate.height)
    fire.layer.position = CGPoint(x: size.width / 2, y: fireTemplate.height * fireScale / 2)
    fire.layer.transform = CATransform3DMakeScale(fireScale, fireScale, 1)
    plane.position = CGPoint(x: size.width / 2, y: size.height / 2)
    let template = PlayfulPropLayout.parachuteTemplateSize
    parachute.layer.bounds = CGRect(origin: .zero, size: template)
    parachute.layer.position = CGPoint(x: size.width / 2, y: size.height / 2)
    parachute.layer.transform = CATransform3DMakeScale(
      size.width / template.width, size.height / template.height, 1)
  }

  func hide() {
    fire.stop()
    parachute.stop()
    for layer in [rope, fire.layer, plane, parachute.layer] {
      layer.isHidden = true
      layer.removeAllAnimations()
      for child in layer.sublayers ?? [] { child.removeAllAnimations() }
    }
  }

  private func configurePlane() {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 55, y: 35))
    path.addLine(to: CGPoint(x: 0, y: 18))
    path.addLine(to: CGPoint(x: 23, y: 13))
    path.addLine(to: CGPoint(x: 28, y: 0))
    path.closeSubpath()
    plane.path = path
    plane.bounds = CGRect(x: 0, y: 0, width: 55, height: 35)
    plane.fillColor = NSColor(hex: "FFF8EC").cgColor
    plane.strokeColor = NSColor(hex: "9786A9").cgColor
    plane.lineWidth = 2
    let fold = CAShapeLayer()
    let crease = CGMutablePath()
    crease.move(to: CGPoint(x: 23, y: 13))
    crease.addLine(to: CGPoint(x: 55, y: 35))
    fold.path = crease
    fold.strokeColor = plane.strokeColor
    fold.lineWidth = 1
    plane.addSublayer(fold)
  }

}
