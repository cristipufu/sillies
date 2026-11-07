import AppKit
import QuartzCore

@MainActor
final class SpartanRig: CharacterRig {
  let crest = CALayer()
  let shield = CALayer()
  let medalShine = CALayer()

  private enum Design {
    static let red = "B95B61"
    static let crimson = "873F50"
    static let bronze = "D8B47C"
    static let outline = "865D59"
    static let skin = "F3D1AD"
    static let face = CGRect(x: 27, y: 55, width: 74, height: 58)
  }

  init() {
    super.init(gripFill: Design.skin, sleeveFill: Design.red, gripOutline: Design.outline)
    drawTunic()
    drawLimbs()
    drawHelmet()
    drawCrest()
    drawShield()
  }

  private func drawTunic() {
    pill(
      on: torso, CGRect(x: 41, y: 28, width: 46, height: 44), Design.red, radius: 14,
      stroke: Design.outline)
    pill(
      on: torso, CGRect(x: 47, y: 45, width: 34, height: 20), Design.bronze, radius: 10,
      stroke: Design.outline)
    line(
      on: torso, points: [CGPoint(x: 53, y: 58), CGPoint(x: 75, y: 58)], color: "F0D8A5", width: 2)
    pill(on: torso, CGRect(x: 40, y: 35, width: 48, height: 7), Design.crimson, radius: 3)
    oval(
      on: torso, CGRect(x: 60, y: 34, width: 9, height: 9), Design.bronze, stroke: Design.outline)
    for x in [45.0, 56, 67, 78] {
      pill(on: torso, CGRect(x: x, y: 25, width: 7, height: 12), Design.crimson, radius: 3)
    }
    addDetail(
      medalShine, to: torso, frame: CGRect(x: 56, y: 49, width: 16, height: 15), restingOpacity: 0)
    medalShine.name = ArtworkHitTester.decorationName
    line(
      on: medalShine, points: [CGPoint(x: 8, y: 1), CGPoint(x: 8, y: 14)], color: "FFF3C3", width: 2
    )
    line(
      on: medalShine, points: [CGPoint(x: 2, y: 7), CGPoint(x: 14, y: 7)], color: "FFF3C3", width: 2
    )
  }

  private func drawLimbs() {
    for (foot, x) in [(leftFoot, 39.0), (rightFoot, 70.0)] {
      softLimb(foot, frame: CGRect(x: x, y: 20, width: 19, height: 15), fill: Design.skin)
      pill(on: foot, CGRect(x: 0, y: 0, width: 19, height: 5), Design.crimson, radius: 2)
      line(
        on: foot, points: [CGPoint(x: 5, y: 4), CGPoint(x: 9, y: 13)], color: Design.outline,
        width: 2)
    }
    for (arm, x) in [(leftArm, 29.0), (rightArm, 84.0)] {
      softLimb(arm, frame: CGRect(x: x, y: 35, width: 15, height: 28), fill: Design.skin)
      arm.anchorPoint = CGPoint(x: 0.5, y: 1)
      arm.position = CGPoint(x: x + 7.5, y: 63)
      pill(
        on: arm, CGRect(x: 0, y: 18, width: 15, height: 12), Design.red, radius: 6,
        stroke: Design.outline)
      pill(on: arm, CGRect(x: 0, y: 8, width: 15, height: 5), Design.bronze, radius: 2)
    }
  }

  private func drawHelmet() {
    head.frame = Design.face
    pill(
      on: head, CGRect(x: 0, y: 0, width: 74, height: 56), Design.red, radius: 27,
      stroke: Design.outline)
    oval(on: head, CGRect(x: 8, y: 5, width: 58, height: 41), Design.skin, stroke: Design.outline)
    makeEyes(in: head, left: 24, right: 50, y: 27, color: "533F47")
    cheeks(on: head, centers: [CGPoint(x: 15, y: 18), CGPoint(x: 59, y: 18)], color: "E9A3A0")
    smile(on: head, center: CGPoint(x: 37, y: 14), width: 12, color: "A86F69")
    let brow = CGMutablePath()
    brow.move(to: CGPoint(x: 6, y: 35))
    brow.addQuadCurve(to: CGPoint(x: 37, y: 39), control: CGPoint(x: 19, y: 43))
    brow.addQuadCurve(to: CGPoint(x: 68, y: 35), control: CGPoint(x: 56, y: 43))
    shape(on: head, path: brow, fill: nil, stroke: Design.bronze, lineWidth: 5)
    for x in [3.0, 59.0] {
      pill(
        on: head, CGRect(x: x, y: 4, width: 12, height: 29), Design.crimson, radius: 5,
        stroke: Design.outline)
      line(
        on: head, points: [CGPoint(x: x + 5, y: 11), CGPoint(x: x + 5, y: 25)],
        color: Design.bronze, width: 2)
    }
    line(
      on: head, points: [CGPoint(x: 14, y: 48), CGPoint(x: 27, y: 51)], color: "E99691", width: 3)
  }

  private func drawCrest() {
    addDetail(crest, to: head, frame: CGRect(x: 19, y: 49, width: 44, height: 23))
    crest.anchorPoint = CGPoint(x: 0.35, y: 0)
    crest.position = CGPoint(x: 34.4, y: 49)
    let plume = CGMutablePath()
    plume.move(to: CGPoint(x: 2, y: 3))
    plume.addCurve(
      to: CGPoint(x: 40, y: 9), control1: CGPoint(x: 2, y: 29), control2: CGPoint(x: 36, y: 25))
    plume.addQuadCurve(to: CGPoint(x: 35, y: 0), control: CGPoint(x: 44, y: 2))
    plume.addQuadCurve(to: CGPoint(x: 2, y: 3), control: CGPoint(x: 15, y: 10))
    plume.closeSubpath()
    shape(on: crest, path: plume, fill: "D87678", stroke: Design.crimson)
    for x in [10.0, 17, 24, 31] {
      line(
        on: crest, points: [CGPoint(x: x, y: 8), CGPoint(x: x + 1, y: 18)], color: "F1AAA0",
        width: 1.7)
    }
    pill(
      on: head, CGRect(x: 28, y: 49, width: 19, height: 7), Design.bronze, radius: 3,
      stroke: Design.outline)
  }

  private func drawShield() {
    addDetail(shield, to: leftArm, frame: CGRect(x: -8, y: -2, width: 29, height: 29))
    oval(on: shield, shield.bounds, Design.bronze, stroke: Design.outline)
    oval(on: shield, CGRect(x: 4, y: 4, width: 21, height: 21), "E9C996", stroke: "BA8E65")
    line(
      on: shield, points: [CGPoint(x: 9, y: 8), CGPoint(x: 14.5, y: 21), CGPoint(x: 20, y: 8)],
      color: Design.crimson, width: 2.8)
  }
}
