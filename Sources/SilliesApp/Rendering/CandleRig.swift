import AppKit
import QuartzCore

@MainActor
final class CandleRig: CharacterRig {
  let flame = CALayer()
  let flameCore = CALayer()
  let glow = CALayer()

  private enum Design {
    static let wax = "F2D69A"
    static let outline = "BC996B"
    static let cream = "FFF0CB"
    static let face = CGRect(x: 35, y: 47, width: 58, height: 46)
    static let flame = CGRect(x: 15, y: 42, width: 30, height: 34)
  }

  init() {
    super.init(gripFill: Design.wax, sleeveFill: Design.wax, gripOutline: Design.outline)
    drawGlow()
    drawBody()
    drawLimbs()
    drawHead()
    drawFlame()
    stage.insertSublayer(leftArm, above: head)
    stage.insertSublayer(rightArm, above: leftArm)
  }

  private func drawGlow() {
    accessory.frame = root.bounds
    addDetail(glow, to: accessory, frame: CGRect(x: 36, y: 83, width: 58, height: 45))
    glow.name = ArtworkHitTester.decorationName
    for frame in [glow.bounds, CGRect(x: 8, y: 6, width: 42, height: 33)] {
      shape(
        on: glow, path: CGPath(ellipseIn: frame, transform: nil), fill: "F5C975", opacity: 0.12)
    }
  }

  private func drawBody() {
    pill(
      on: torso, CGRect(x: 35, y: 26, width: 58, height: 50), Design.wax, radius: 17,
      stroke: Design.outline)
    pill(on: torso, CGRect(x: 42, y: 31, width: 9, height: 30), "FBE5B4", radius: 4)
    oval(on: torso, CGRect(x: 43, y: 26, width: 42, height: 9), "E8C283")
  }

  private func drawLimbs() {
    for (foot, x) in [(leftFoot, 39.0), (rightFoot, 70.0)] {
      softLimb(foot, frame: CGRect(x: x, y: 20, width: 19, height: 14), fill: Design.wax)
    }
    for (arm, x) in [(leftArm, 29.0), (rightArm, 85.0)] {
      softLimb(arm, frame: CGRect(x: x, y: 35, width: 14, height: 25), fill: Design.wax)
      arm.anchorPoint = CGPoint(x: 0.5, y: 1)
      arm.position = CGPoint(x: x + 7, y: 60)
    }
  }

  private func drawHead() {
    head.frame = Design.face
    // The lower edge overlaps the body, giving Flick one continuous candle silhouette.
    let wax = CGMutablePath()
    wax.move(to: CGPoint(x: 0, y: 0))
    wax.addLine(to: CGPoint(x: 0, y: 33))
    wax.addCurve(
      to: CGPoint(x: 58, y: 33), control1: CGPoint(x: 0, y: 49), control2: CGPoint(x: 58, y: 49))
    wax.addLine(to: CGPoint(x: 58, y: 0))
    shape(on: head, path: wax, fill: Design.wax, stroke: Design.outline)
    let drips = CGMutablePath()
    drips.move(to: CGPoint(x: 1, y: 34))
    drips.addCurve(
      to: CGPoint(x: 57, y: 34), control1: CGPoint(x: 3, y: 47), control2: CGPoint(x: 55, y: 47))
    drips.addLine(to: CGPoint(x: 57, y: 25))
    drips.addQuadCurve(to: CGPoint(x: 45, y: 25), control: CGPoint(x: 51, y: 17))
    drips.addLine(to: CGPoint(x: 45, y: 30))
    drips.addQuadCurve(to: CGPoint(x: 33, y: 30), control: CGPoint(x: 39, y: 37))
    drips.addQuadCurve(to: CGPoint(x: 17, y: 29), control: CGPoint(x: 25, y: 22))
    drips.addLine(to: CGPoint(x: 17, y: 23))
    drips.addQuadCurve(to: CGPoint(x: 5, y: 23), control: CGPoint(x: 11, y: 14))
    drips.addLine(to: CGPoint(x: 5, y: 30))
    drips.closeSubpath()
    shape(on: head, path: drips, fill: Design.cream)
    oval(on: head, CGRect(x: 8, y: 34, width: 42, height: 10), "E8BC7C", stroke: Design.outline)
    line(
      on: head, points: [CGPoint(x: 29, y: 38), CGPoint(x: 30, y: 47)], color: "796147", width: 2.5)
    makeEyes(in: head, left: 17, right: 41, y: 16, color: "695342")
    cheeks(on: head, centers: [CGPoint(x: 7, y: 8), CGPoint(x: 51, y: 8)], color: "E4A48D")
    smile(on: head, center: CGPoint(x: 29, y: 6), width: 11, color: "A87964")
  }

  private func drawFlame() {
    addDetail(flame, to: head, frame: Design.flame)
    flame.anchorPoint = CGPoint(x: 0.5, y: 0)
    flame.position = CGPoint(x: Design.flame.midX, y: Design.flame.minY)
    let outer = CGMutablePath()
    outer.move(to: CGPoint(x: 15, y: 0))
    outer.addCurve(
      to: CGPoint(x: 18, y: 34), control1: CGPoint(x: -8, y: 4), control2: CGPoint(x: 6, y: 25))
    outer.addCurve(
      to: CGPoint(x: 27, y: 12), control1: CGPoint(x: 16, y: 24), control2: CGPoint(x: 31, y: 23))
    outer.addQuadCurve(to: CGPoint(x: 15, y: 0), control: CGPoint(x: 29, y: 1))
    outer.closeSubpath()
    shape(on: flame, path: outer, fill: "F2B36F", stroke: "D99560", lineWidth: 1.5)
    addDetail(flameCore, to: flame, frame: CGRect(x: 7, y: 2, width: 17, height: 22))
    let inner = CGMutablePath()
    inner.move(to: CGPoint(x: 8, y: 0))
    inner.addCurve(
      to: CGPoint(x: 10, y: 22), control1: CGPoint(x: -5, y: 3), control2: CGPoint(x: 7, y: 16))
    inner.addCurve(
      to: CGPoint(x: 8, y: 0), control1: CGPoint(x: 8, y: 15), control2: CGPoint(x: 24, y: 5))
    inner.closeSubpath()
    shape(on: flameCore, path: inner, fill: "FFF0B5")
  }
}
