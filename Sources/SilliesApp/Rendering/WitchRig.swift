import AppKit
import QuartzCore

@MainActor
final class WitchRig: CharacterRig {
  let hat = CALayer()
  let hatCharm = CALayer()
  let spellStar = CALayer()

  private enum Design {
    static let skin = "F4D6BE"
    static let hair = "524458"
    static let plum = "9982B5"
    static let outline = "78638D"
    static let coat = "F6D996"
    static let gold = "E9B965"
    static let face = CGRect(x: 28, y: 52, width: 72, height: 57)
  }

  init() {
    super.init(gripFill: Design.skin, sleeveFill: Design.coat, gripOutline: Design.outline)
    drawCoat()
    drawLimbs()
    drawHead()
    drawHat()
    addDetail(
      spellStar, to: stage, frame: CGRect(x: 94, y: 83, width: 15, height: 15), restingOpacity: 0)
    spellStar.name = ArtworkHitTester.decorationName
    drawStar(on: spellStar)
  }

  private func drawCoat() {
    let coat = CGMutablePath()
    coat.move(to: CGPoint(x: 44, y: 67))
    coat.addQuadCurve(to: CGPoint(x: 36, y: 29), control: CGPoint(x: 36, y: 47))
    coat.addQuadCurve(to: CGPoint(x: 92, y: 29), control: CGPoint(x: 64, y: 21))
    coat.addQuadCurve(to: CGPoint(x: 84, y: 67), control: CGPoint(x: 91, y: 47))
    coat.closeSubpath()
    shape(on: torso, path: coat, fill: Design.coat, stroke: "B99B74")
    line(
      on: torso, points: [CGPoint(x: 64, y: 30), CGPoint(x: 64, y: 61)], color: "D7B981", width: 1.4
    )
    for y in [38.0, 48.0, 58.0] {
      oval(on: torso, CGRect(x: 61, y: y, width: 5, height: 5), Design.plum)
    }
    pill(on: torso, CGRect(x: 41, y: 59, width: 46, height: 9), "EAC384", radius: 4)
  }

  private func drawLimbs() {
    for (foot, x) in [(leftFoot, 40.0), (rightFoot, 69.0)] {
      softLimb(foot, frame: CGRect(x: x, y: 20, width: 19, height: 15), fill: Design.plum)
      pill(on: foot, CGRect(x: 1, y: 2, width: 17, height: 4), "B6A2CE", radius: 2)
    }
    for (arm, x) in [(leftArm, 29.0), (rightArm, 84.0)] {
      softLimb(arm, frame: CGRect(x: x, y: 34, width: 15, height: 29), fill: Design.coat)
      arm.anchorPoint = CGPoint(x: 0.5, y: 1)
      arm.position = CGPoint(x: x + 7.5, y: 63)
      pill(on: arm, CGRect(x: 1, y: 0, width: 13, height: 10), Design.skin, stroke: "BE9C91")
      pill(on: arm, CGRect(x: 0, y: 10, width: 15, height: 5), "FBE7B7", radius: 2)
    }
  }

  private func drawHead() {
    head.frame = Design.face
    pill(
      on: head, CGRect(x: 0, y: 0, width: 72, height: 56), Design.hair, radius: 24, stroke: "43384B"
    )
    oval(on: head, CGRect(x: 7, y: 4, width: 58, height: 45), Design.skin, stroke: "BE9C91")
    let fringe = CGMutablePath()
    fringe.move(to: CGPoint(x: 6, y: 42))
    fringe.addQuadCurve(to: CGPoint(x: 38, y: 53), control: CGPoint(x: 17, y: 59))
    fringe.addQuadCurve(to: CGPoint(x: 66, y: 37), control: CGPoint(x: 64, y: 53))
    fringe.addQuadCurve(to: CGPoint(x: 35, y: 40), control: CGPoint(x: 45, y: 34))
    fringe.addQuadCurve(to: CGPoint(x: 9, y: 27), control: CGPoint(x: 26, y: 28))
    fringe.closeSubpath()
    shape(on: head, path: fringe, fill: Design.hair)
    makeEyes(in: head, left: 23, right: 49, y: 25, color: "514052")
    cheeks(on: head, centers: [CGPoint(x: 14, y: 14), CGPoint(x: 58, y: 14)], color: "E7A9A6")
    smile(on: head, center: CGPoint(x: 36, y: 12), width: 11, color: "AC7C7C")
  }

  private func drawHat() {
    let frame = CGRect(x: -11, y: 39, width: 94, height: 36)
    addDetail(hat, to: head, frame: frame)
    hat.anchorPoint = CGPoint(x: 0.5, y: 0)
    hat.position = CGPoint(x: frame.midX, y: frame.minY)
    let cone = CGMutablePath()
    cone.move(to: CGPoint(x: 19, y: 8))
    cone.addQuadCurve(to: CGPoint(x: 43, y: 35), control: CGPoint(x: 30, y: 27))
    cone.addCurve(
      to: CGPoint(x: 79, y: 25), control1: CGPoint(x: 55, y: 37), control2: CGPoint(x: 56, y: 20))
    cone.addQuadCurve(to: CGPoint(x: 65, y: 19), control: CGPoint(x: 76, y: 16))
    cone.addLine(to: CGPoint(x: 76, y: 8))
    cone.closeSubpath()
    shape(on: hat, path: cone, fill: Design.plum, stroke: Design.outline)
    pill(on: hat, CGRect(x: 24, y: 8, width: 49, height: 9), "C0A6CC", radius: 4)
    oval(on: hat, CGRect(x: 1, y: 0, width: 92, height: 13), Design.plum, stroke: Design.outline)
    line(on: hat, points: [CGPoint(x: 15, y: 8), CGPoint(x: 31, y: 10)], color: "C5AED8", width: 2)
    addDetail(hatCharm, to: hat, frame: CGRect(x: 75, y: 7, width: 11, height: 19))
    hatCharm.anchorPoint = CGPoint(x: 0.5, y: 1)
    hatCharm.position = CGPoint(x: 80.5, y: 26)
    line(
      on: hatCharm, points: [CGPoint(x: 5.5, y: 10), CGPoint(x: 5.5, y: 18)], color: Design.gold,
      width: 1.2)
    drawStar(on: hatCharm)
  }

  private func drawStar(on layer: CALayer) {
    let diameter = layer.bounds.width
    let star = CGMutablePath()
    for point in 0..<10 {
      let angle = CGFloat.pi / 2 + CGFloat(point) * CGFloat.pi / 5
      let radius = diameter * (point.isMultiple(of: 2) ? 0.5 : 0.23)
      let position = CGPoint(
        x: diameter / 2 + cos(angle) * radius, y: diameter / 2 + sin(angle) * radius)
      if point == 0 { star.move(to: position) } else { star.addLine(to: position) }
    }
    star.closeSubpath()
    shape(on: layer, path: star, fill: "FFE3A0", stroke: Design.gold, lineWidth: 1.2)
  }
}
