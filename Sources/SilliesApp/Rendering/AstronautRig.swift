import AppKit
import QuartzCore

@MainActor
final class AstronautRig: CharacterRig {
  let visorShine = CALayer()
  let wristDisplay = CALayer()
  let thrusters = CALayer()

  private enum Design {
    static let suit = "F2EEE4"
    static let outline = "8A99A8"
    static let slate = "738BA4"
    static let coral = "D6927D"
    static let face = CGRect(x: 24, y: 52, width: 80, height: 68)
  }

  init() {
    super.init(gripFill: Design.suit, sleeveFill: Design.suit, gripOutline: Design.outline)
    drawBackpack()
    drawSuit()
    drawLimbs()
    drawHelmet()
  }

  private func drawBackpack() {
    accessory.frame = root.bounds
    pill(
      on: accessory, CGRect(x: 29, y: 35, width: 70, height: 40), "C2CDD7", radius: 9,
      stroke: Design.outline)
    for x in [24.0, 91.0] {
      pill(
        on: accessory, CGRect(x: x, y: 36, width: 13, height: 35), "D4DBE1", radius: 6,
        stroke: Design.outline)
      pill(on: accessory, CGRect(x: x, y: 42, width: 13, height: 5), Design.coral, radius: 2)
    }
    addDetail(
      thrusters, to: accessory, frame: CGRect(x: 24, y: 24, width: 80, height: 15),
      restingOpacity: 0)
    thrusters.name = ArtworkHitTester.decorationName
    for x in [1.0, 68.0] {
      oval(on: thrusters, CGRect(x: x, y: 0, width: 10, height: 14), "F1C694")
      oval(on: thrusters, CGRect(x: x + 3, y: 6, width: 4, height: 7), "FFF1C8")
    }
  }

  private func drawSuit() {
    pill(
      on: torso, CGRect(x: 39, y: 27, width: 50, height: 46), Design.suit, radius: 17,
      stroke: Design.outline)
    pill(on: torso, CGRect(x: 40, y: 30, width: 48, height: 8), "D1DBDF", radius: 3)
    pill(
      on: torso, CGRect(x: 49, y: 43, width: 30, height: 23), Design.slate, radius: 6,
      stroke: Design.outline)
    pill(on: torso, CGRect(x: 54, y: 53, width: 20, height: 8), "B8DAD7", radius: 2)
    for (x, color) in [(55.0, "ECC78D"), (64.0, Design.coral)] {
      oval(on: torso, CGRect(x: x, y: 46, width: 5, height: 5), color)
    }
    line(
      on: torso, points: [CGPoint(x: 43, y: 65), CGPoint(x: 85, y: 65)], color: "D6D9D7", width: 3)
  }

  private func drawLimbs() {
    for (foot, x) in [(leftFoot, 36.0), (rightFoot, 72.0)] {
      softLimb(foot, frame: CGRect(x: x, y: 20, width: 21, height: 17), fill: Design.suit)
      pill(on: foot, CGRect(x: 0, y: 0, width: 21, height: 6), Design.slate, radius: 3)
      line(
        on: foot, points: [CGPoint(x: 4, y: 11), CGPoint(x: 17, y: 11)], color: "D2D9DC", width: 2)
    }
    for (arm, x) in [(leftArm, 27.0), (rightArm, 85.0)] {
      softLimb(arm, frame: CGRect(x: x, y: 34, width: 16, height: 29), fill: Design.suit)
      arm.anchorPoint = CGPoint(x: 0.5, y: 1)
      arm.position = CGPoint(x: x + 8, y: 63)
      pill(on: arm, CGRect(x: 0, y: 9, width: 16, height: 6), Design.coral, radius: 2)
      line(
        on: arm, points: [CGPoint(x: 4, y: 4), CGPoint(x: 12, y: 4)], color: Design.outline,
        width: 1.2)
    }
    addDetail(wristDisplay, to: rightArm, frame: CGRect(x: 3, y: 10, width: 10, height: 8))
    pill(on: wristDisplay, wristDisplay.bounds, "BDE4DB", radius: 2, stroke: Design.slate)
  }

  private func drawHelmet() {
    head.frame = Design.face
    oval(on: head, CGRect(x: 0, y: 0, width: 80, height: 67), Design.suit, stroke: Design.outline)
    oval(on: head, CGRect(x: 7, y: 10, width: 66, height: 49), Design.slate, stroke: "667D95")
    oval(on: head, CGRect(x: 12, y: 14, width: 56, height: 41), "D6E7E4")
    oval(on: head, CGRect(x: 17, y: 15, width: 46, height: 33), "F2D5B4")
    makeEyes(in: head, left: 29, right: 51, y: 34, color: "4E5766")
    cheeks(on: head, centers: [CGPoint(x: 23, y: 25), CGPoint(x: 57, y: 25)], color: "E1A69B")
    smile(on: head, center: CGPoint(x: 40, y: 24), width: 10, color: "A47E77")
    for x in [0.0, 72.0] {
      pill(
        on: head, CGRect(x: x, y: 24, width: 8, height: 18), "C3CFD8", radius: 3,
        stroke: Design.outline)
    }
    addDetail(visorShine, to: head, frame: CGRect(x: 11, y: 39, width: 23, height: 17))
    visorShine.name = ArtworkHitTester.decorationName
    let shine = CGMutablePath()
    shine.move(to: CGPoint(x: 1, y: 2))
    shine.addQuadCurve(to: CGPoint(x: 19, y: 13), control: CGPoint(x: 5, y: 13))
    shape(on: visorShine, path: shine, fill: nil, stroke: "FAFCF4", lineWidth: 3, opacity: 0.9)
    pill(on: head, CGRect(x: 26, y: 1, width: 28, height: 6), Design.coral, radius: 3)
  }
}
