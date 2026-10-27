import AppKit
import QuartzCore

@MainActor
final class HedgehogRig: CharacterRig {
  let curlShell = CALayer()

  private enum Design {
    static let cocoa = "9E7D70"
    static let outline = "796159"
    static let cream = "F2DEC0"
    static let body = CGRect(x: 25, y: 26, width: 78, height: 77)
    static let face = CGRect(x: 34, y: 49, width: 60, height: 57)
    static let feet = [
      CGRect(x: 37, y: 20, width: 21, height: 15), CGRect(x: 70, y: 20, width: 21, height: 15),
    ]
    static let arms = [
      CGRect(x: 28, y: 37, width: 17, height: 24), CGRect(x: 83, y: 37, width: 17, height: 24),
    ]
    static let shell = CGRect(x: 25, y: 22, width: 78, height: 78)
    static let spineCount = 18
    static let outerRadius: CGFloat = 39
    static let innerRadius: CGFloat = 33
  }

  init() {
    super.init(gripFill: Design.cream, sleeveFill: Design.cream, gripOutline: Design.outline)
    accessory.frame = Design.body
    drawSpines(on: accessory)
    oval(
      on: torso, CGRect(x: 38, y: 25, width: 52, height: 52), Design.cream, stroke: Design.outline)
    for (part, frame) in zip([leftFoot, rightFoot], Design.feet) {
      softLimb(part, frame: frame, fill: "D4B69A")
    }
    for (part, frame) in zip([leftArm, rightArm], Design.arms) {
      softLimb(part, frame: frame, fill: Design.cream)
    }
    drawHead()
    addDetail(curlShell, to: stage, frame: Design.shell, restingOpacity: 0)
    drawSpines(on: curlShell)
    drawShellSpiral()
  }

  private func drawSpines(on layer: CALayer) {
    let outline = CGMutablePath()
    let center = CGPoint(x: Design.outerRadius, y: Design.outerRadius)
    let points = (0..<(Design.spineCount * 2)).map { index in
      let angle = CGFloat(index) * .pi / CGFloat(Design.spineCount)
      let radius = index.isMultiple(of: 2) ? Design.outerRadius : Design.innerRadius
      return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
    outline.addLines(between: points)
    outline.closeSubpath()
    shape(on: layer, path: outline, fill: Design.cocoa, stroke: Design.outline)
    for point in [
      CGPoint(x: 23, y: 58), CGPoint(x: 40, y: 65), CGPoint(x: 55, y: 54), CGPoint(x: 14, y: 38),
      CGPoint(x: 62, y: 35),
    ] {
      line(
        on: layer, points: [point, CGPoint(x: point.x + 2, y: point.y - 7)], color: "C2A18A",
        width: 2)
    }
  }

  private func drawHead() {
    head.frame = Design.face
    for x in [3.0, 43.0] {
      oval(
        on: head, CGRect(x: x, y: 37, width: 15, height: 17), Design.cream, stroke: Design.outline)
      oval(on: head, CGRect(x: x + 4, y: 41, width: 7, height: 9), "DDB39E")
    }
    let face = CGMutablePath()
    face.move(to: CGPoint(x: 30, y: 0))
    face.addCurve(
      to: CGPoint(x: 2, y: 31), control1: CGPoint(x: 22, y: 9), control2: CGPoint(x: -2, y: 8))
    face.addCurve(
      to: CGPoint(x: 58, y: 31), control1: CGPoint(x: 5, y: 64), control2: CGPoint(x: 55, y: 64))
    face.addCurve(
      to: CGPoint(x: 30, y: 0), control1: CGPoint(x: 62, y: 8), control2: CGPoint(x: 38, y: 9))
    face.closeSubpath()
    shape(on: head, path: face, fill: Design.cream, stroke: Design.outline)
    makeEyes(in: head, left: 17, right: 43, y: 29, color: "5E4A45")
    cheeks(on: head, centers: [CGPoint(x: 9, y: 18), CGPoint(x: 51, y: 18)], color: "DFAE97")
    oval(on: head, CGRect(x: 25, y: 10, width: 10, height: 7), "79615E")
    oval(on: head, CGRect(x: 27, y: 14, width: 3, height: 2), "E6CBC0")
  }

  private func drawShellSpiral() {
    let spiral = CGMutablePath()
    spiral.move(to: CGPoint(x: 54, y: 28))
    spiral.addCurve(
      to: CGPoint(x: 25, y: 49), control1: CGPoint(x: 15, y: 10), control2: CGPoint(x: 11, y: 51))
    spiral.addCurve(
      to: CGPoint(x: 48, y: 37), control1: CGPoint(x: 49, y: 61), control2: CGPoint(x: 63, y: 39))
    shape(on: curlShell, path: spiral, fill: nil, stroke: "C7A58D", lineWidth: 3)
  }
}
