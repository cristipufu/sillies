import AppKit
import QuartzCore

@MainActor
final class PenguinRig: CharacterRig {
  let bowTie = CALayer()

  private enum Design {
    static let slate = "748B9E"
    static let outline = "52677E"
    static let cream = "FFF2D7"
    static let gold = "EBC187"
    static let body = CGRect(x: 28, y: 23, width: 72, height: 80)
    static let face = CGRect(x: 28, y: 62, width: 72, height: 52)
    static let feet = [
      CGRect(x: 31, y: 20, width: 28, height: 14), CGRect(x: 69, y: 20, width: 28, height: 14),
    ]
    static let flippers = [
      CGRect(x: 14, y: 37, width: 26, height: 42), CGRect(x: 88, y: 37, width: 26, height: 42),
    ]
    static let bow = CGRect(x: 50, y: 53, width: 28, height: 15)
  }

  init() {
    super.init(gripFill: Design.slate, sleeveFill: Design.slate, gripOutline: Design.outline)
    oval(on: torso, Design.body, Design.slate, stroke: Design.outline)
    oval(on: torso, CGRect(x: 40, y: 27, width: 48, height: 65), Design.cream)
    for (part, frame) in zip([leftFoot, rightFoot], Design.feet) {
      softLimb(part, frame: frame, fill: Design.gold)
    }
    for (part, frame) in zip([leftArm, rightArm], Design.flippers) {
      part.frame = frame
      drawFlipper(on: part)
    }
    drawHead()
    drawBowTie()
  }

  private func drawFlipper(on layer: CALayer) {
    let fin = CGMutablePath()
    fin.move(to: CGPoint(x: 17, y: 40))
    fin.addCurve(
      to: CGPoint(x: 5, y: 1), control1: CGPoint(x: 0, y: 33), control2: CGPoint(x: -1, y: 4))
    fin.addCurve(
      to: CGPoint(x: 17, y: 40), control1: CGPoint(x: 21, y: 4), control2: CGPoint(x: 31, y: 31))
    fin.closeSubpath()
    shape(on: layer, path: fin, fill: Design.slate, stroke: Design.outline)
  }

  private func drawHead() {
    head.frame = Design.face
    oval(on: head, head.bounds, Design.slate, stroke: Design.outline)
    for x in [10.0, 34.0] {
      oval(on: head, CGRect(x: x, y: 3, width: 28, height: 39), Design.cream)
    }
    makeEyes(in: head, left: 25, right: 47, y: 25, color: "364C61")
    cheeks(on: head, centers: [CGPoint(x: 15, y: 13), CGPoint(x: 57, y: 13)], color: "E7B2A5")
    let beak = CGMutablePath()
    beak.move(to: CGPoint(x: 29, y: 18))
    beak.addQuadCurve(to: CGPoint(x: 43, y: 18), control: CGPoint(x: 36, y: 23))
    beak.addQuadCurve(to: CGPoint(x: 29, y: 18), control: CGPoint(x: 36, y: 8))
    beak.closeSubpath()
    shape(on: head, path: beak, fill: Design.gold, stroke: "BD986A", lineWidth: 1.2)
    let tuft = CGMutablePath()
    tuft.move(to: CGPoint(x: 28, y: 47))
    tuft.addQuadCurve(to: CGPoint(x: 44, y: 53), control: CGPoint(x: 25, y: 61))
    shape(on: head, path: tuft, fill: nil, stroke: Design.outline, lineWidth: 3)
  }

  private func drawBowTie() {
    addDetail(bowTie, to: stage, frame: Design.bow)
    let bow = CGMutablePath()
    bow.addLines(between: [CGPoint(x: 0, y: 1), CGPoint(x: 14, y: 7), CGPoint(x: 0, y: 14)])
    bow.closeSubpath()
    bow.addLines(between: [CGPoint(x: 28, y: 1), CGPoint(x: 14, y: 7), CGPoint(x: 28, y: 14)])
    bow.closeSubpath()
    shape(on: bowTie, path: bow, fill: "A7C4B8", stroke: "739A8E", lineWidth: 1.5)
    oval(on: bowTie, CGRect(x: 10, y: 4, width: 8, height: 8), "84AA9C")
  }
}
