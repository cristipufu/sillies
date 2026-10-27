import AppKit
import QuartzCore

@MainActor
final class DragonRig: CharacterRig {
  let leftWing = CALayer()
  let rightWing = CALayer()
  let tail = CALayer()
  let spark = CALayer()

  private enum Design {
    static let lavender = "B8A4D9"
    static let outline = "8874AA"
    static let gold = "F6DCA1"
    static let body = CGRect(x: 38, y: 25, width: 52, height: 53)
    static let face = CGRect(x: 27, y: 57, width: 74, height: 60)
    static let feet = [
      CGRect(x: 34, y: 20, width: 25, height: 17), CGRect(x: 69, y: 20, width: 25, height: 17),
    ]
    static let arms = [
      CGRect(x: 27, y: 38, width: 17, height: 28), CGRect(x: 84, y: 38, width: 17, height: 28),
    ]
    static let wings = [
      CGRect(x: 10, y: 47, width: 35, height: 44), CGRect(x: 83, y: 47, width: 35, height: 44),
    ]
    static let tail = CGRect(x: 77, y: 22, width: 44, height: 42)
    static let spark = CGRect(x: 103, y: 69, width: 18, height: 18)
  }

  init() {
    super.init(gripFill: Design.lavender, sleeveFill: Design.lavender, gripOutline: Design.outline)
    accessory.frame = root.bounds
    drawTail()
    for (wing, frame) in zip([leftWing, rightWing], Design.wings) {
      addDetail(wing, to: accessory, frame: frame)
      drawWing(on: wing)
    }
    oval(on: torso, Design.body, Design.lavender, stroke: Design.outline)
    oval(on: torso, CGRect(x: 47, y: 27, width: 34, height: 40), Design.gold)
    for y in [36.0, 46.0, 56.0] {
      smile(on: torso, center: CGPoint(x: 64, y: y), width: 24, color: "DABB88")
    }
    for (part, frame) in zip([leftFoot, rightFoot], Design.feet) {
      softLimb(part, frame: frame, fill: Design.lavender)
    }
    for (part, frame) in zip([leftArm, rightArm], Design.arms) {
      softLimb(part, frame: frame, fill: Design.lavender)
    }
    drawHead()
    drawSpark()
  }

  private func drawTail() {
    addDetail(tail, to: accessory, frame: Design.tail)
    let curl = CGMutablePath()
    curl.move(to: CGPoint(x: 0, y: 9))
    curl.addCurve(
      to: CGPoint(x: 33, y: 31), control1: CGPoint(x: 34, y: -2), control2: CGPoint(x: 44, y: 21))
    shape(on: tail, path: curl, fill: nil, stroke: Design.outline, lineWidth: 13)
    shape(on: tail, path: curl, fill: nil, stroke: Design.lavender, lineWidth: 9)
    let tip = CGMutablePath()
    tip.addLines(between: [CGPoint(x: 25, y: 28), CGPoint(x: 30, y: 41), CGPoint(x: 39, y: 29)])
    tip.closeSubpath()
    shape(on: tail, path: tip, fill: Design.gold, stroke: Design.outline)
  }

  private func drawWing(on layer: CALayer) {
    let wing = CGMutablePath()
    wing.move(to: CGPoint(x: 29, y: 0))
    wing.addQuadCurve(to: CGPoint(x: 6, y: 41), control: CGPoint(x: 29, y: 32))
    wing.addQuadCurve(to: CGPoint(x: 1, y: 15), control: CGPoint(x: 0, y: 32))
    wing.addQuadCurve(to: CGPoint(x: 13, y: 16), control: CGPoint(x: 9, y: 23))
    wing.addQuadCurve(to: CGPoint(x: 17, y: 5), control: CGPoint(x: 20, y: 15))
    wing.closeSubpath()
    shape(on: layer, path: wing, fill: "DCC2DC", stroke: Design.outline)
    line(
      on: layer, points: [CGPoint(x: 29, y: 0), CGPoint(x: 6, y: 36)], color: "B49AC5", width: 1.5)
  }

  private func drawHead() {
    head.frame = Design.face
    for x in [12.0, 51.0] {
      let horn = CGMutablePath()
      horn.move(to: CGPoint(x: x, y: 43))
      horn.addQuadCurve(to: CGPoint(x: x + 8, y: 64), control: CGPoint(x: x - 1, y: 61))
      horn.addLine(to: CGPoint(x: x + 14, y: 44))
      horn.closeSubpath()
      shape(on: head, path: horn, fill: Design.gold, stroke: Design.outline)
    }
    oval(
      on: head, CGRect(x: 0, y: 0, width: 74, height: 53), Design.lavender, stroke: Design.outline)
    oval(on: head, CGRect(x: 18, y: 3, width: 44, height: 24), "E3C5DA")
    makeEyes(in: head, left: 24, right: 51, y: 31, color: "5D4C77")
    cheeks(on: head, centers: [CGPoint(x: 12, y: 19), CGPoint(x: 64, y: 19)], color: "D994B5")
    smile(on: head, center: CGPoint(x: 39, y: 13), width: 21, color: Design.outline)
    for x in [33.0, 45.0] {
      oval(on: head, CGRect(x: x, y: 21, width: 3, height: 2), Design.outline)
    }
  }

  private func drawSpark() {
    addDetail(spark, to: stage, frame: Design.spark, restingOpacity: 0)
    spark.name = ArtworkHitTester.decorationName
    let star = CGMutablePath()
    star.addLines(between: [
      CGPoint(x: 9, y: 18), CGPoint(x: 12, y: 11), CGPoint(x: 18, y: 9), CGPoint(x: 12, y: 6),
      CGPoint(x: 9, y: 0), CGPoint(x: 6, y: 6), CGPoint(x: 0, y: 9), CGPoint(x: 6, y: 11),
    ])
    star.closeSubpath()
    shape(on: spark, path: star, fill: "F3C77B", stroke: "DC9E6B", lineWidth: 1)
  }
}
