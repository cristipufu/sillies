import AppKit
import QuartzCore

@MainActor
final class BunnyRig: CharacterRig {
  let leftEar = CALayer()
  let rightEar = CALayer()
  let nose = CALayer()

  private enum Design {
    static let ivory = "FFF0DA"
    static let outline = "B39A8A"
    static let peach = "EDBAAC"
    static let body = CGRect(x: 39, y: 26, width: 50, height: 48)
    static let face = CGRect(x: 29, y: 56, width: 70, height: 49)
    static let feet = [
      CGRect(x: 33, y: 20, width: 27, height: 17), CGRect(x: 68, y: 20, width: 27, height: 17),
    ]
    static let arms = [
      CGRect(x: 30, y: 36, width: 16, height: 27), CGRect(x: 82, y: 36, width: 16, height: 27),
    ]
    static let uprightEar = CGRect(x: 7, y: 34, width: 19, height: 37)
    static let floppyEar = CGRect(x: 43, y: 26, width: 29, height: 43)
    static let nose = CGRect(x: 31, y: 17, width: 8, height: 6)
  }

  init() {
    super.init(gripFill: Design.ivory, sleeveFill: Design.ivory, gripOutline: Design.outline)
    accessory.frame = CGRect(x: 84, y: 29, width: 22, height: 22)
    oval(on: accessory, accessory.bounds, Design.ivory, stroke: Design.outline)
    oval(on: torso, Design.body, Design.ivory, stroke: Design.outline)
    oval(on: torso, CGRect(x: 49, y: 30, width: 30, height: 31), "FFFFFF")
    for (part, frame) in zip([leftFoot, rightFoot], Design.feet) {
      softLimb(part, frame: frame, fill: Design.ivory)
    }
    for (part, frame) in zip([leftArm, rightArm], Design.arms) {
      softLimb(part, frame: frame, fill: Design.ivory)
    }
    drawHead()
  }

  private func drawHead() {
    head.frame = Design.face
    drawEars()
    oval(on: head, head.bounds, Design.ivory, stroke: Design.outline)
    oval(on: head, CGRect(x: 18, y: 2, width: 34, height: 24), "FFF9EE")
    makeEyes(in: head, left: 23, right: 47, y: 28, color: "6C5554")
    cheeks(on: head, centers: [CGPoint(x: 12, y: 18), CGPoint(x: 58, y: 18)], color: Design.peach)
    addDetail(nose, to: head, frame: Design.nose)
    pill(on: nose, nose.bounds, "C88D8C", radius: 3)
    line(
      on: head, points: [CGPoint(x: 35, y: 18), CGPoint(x: 35, y: 13)], color: "A87F7B", width: 1.5)
    smile(on: head, center: CGPoint(x: 31, y: 13), width: 8, color: "A87F7B")
    smile(on: head, center: CGPoint(x: 39, y: 13), width: 8, color: "A87F7B")
  }

  private func drawEars() {
    addDetail(leftEar, to: head, frame: Design.uprightEar)
    pill(on: leftEar, leftEar.bounds, Design.ivory, stroke: Design.outline)
    pill(on: leftEar, CGRect(x: 5, y: 5, width: 9, height: 28), Design.peach)
    addDetail(rightEar, to: head, frame: Design.floppyEar)
    let ear = CGMutablePath()
    ear.move(to: CGPoint(x: 0, y: 1))
    ear.addCurve(
      to: CGPoint(x: 27, y: 29), control1: CGPoint(x: -2, y: 49), control2: CGPoint(x: 30, y: 51))
    ear.addCurve(
      to: CGPoint(x: 12, y: 23), control1: CGPoint(x: 26, y: 14), control2: CGPoint(x: 15, y: 15))
    ear.addLine(to: CGPoint(x: 12, y: 0))
    ear.closeSubpath()
    shape(on: rightEar, path: ear, fill: Design.ivory, stroke: Design.outline)
    let inner = CGMutablePath()
    inner.move(to: CGPoint(x: 8, y: 12))
    inner.addQuadCurve(to: CGPoint(x: 21, y: 27), control: CGPoint(x: 8, y: 46))
    shape(on: rightEar, path: inner, fill: nil, stroke: Design.peach, lineWidth: 6)
  }
}
