import AppKit
import QuartzCore

@MainActor
final class AxolotlRig: CharacterRig {
  let leftGills = CALayer()
  let rightGills = CALayer()
  let tail = CALayer()

  private enum Design {
    static let pink = "F3C6D0"
    static let outline = "BB899F"
    static let gill = "DB94B1"
    static let body = CGRect(x: 39, y: 25, width: 50, height: 51)
    static let face = CGRect(x: 25, y: 58, width: 78, height: 53)
    static let feet = [
      CGRect(x: 37, y: 20, width: 22, height: 16), CGRect(x: 69, y: 20, width: 22, height: 16),
    ]
    static let arms = [
      CGRect(x: 29, y: 37, width: 16, height: 27), CGRect(x: 83, y: 37, width: 16, height: 27),
    ]
    static let tail = CGRect(x: 77, y: 25, width: 39, height: 49)
    static let gills = CGRect(x: -13, y: 5, width: 28, height: 45)
  }

  init() {
    super.init(gripFill: Design.pink, sleeveFill: Design.pink, gripOutline: Design.outline)
    drawTail()
    oval(on: torso, Design.body, Design.pink, stroke: Design.outline)
    oval(on: torso, CGRect(x: 49, y: 29, width: 30, height: 33), "FFE7DF")
    for (part, frame) in zip([leftFoot, rightFoot], Design.feet) {
      softLimb(part, frame: frame, fill: Design.pink)
    }
    for (part, frame) in zip([leftArm, rightArm], Design.arms) {
      softLimb(part, frame: frame, fill: Design.pink)
    }
    drawHead()
  }

  private func drawTail() {
    accessory.frame = root.bounds
    addDetail(tail, to: accessory, frame: Design.tail)
    let fin = CGMutablePath()
    fin.move(to: CGPoint(x: 0, y: 8))
    fin.addCurve(
      to: CGPoint(x: 34, y: 47), control1: CGPoint(x: 29, y: 4), control2: CGPoint(x: 16, y: 42))
    fin.addCurve(
      to: CGPoint(x: 0, y: 0), control1: CGPoint(x: 50, y: 13), control2: CGPoint(x: 28, y: -6))
    fin.closeSubpath()
    shape(on: tail, path: fin, fill: "E6AEC5", stroke: Design.outline)
    let spine = CGMutablePath()
    spine.move(to: CGPoint(x: 3, y: 5))
    spine.addQuadCurve(to: CGPoint(x: 31, y: 37), control: CGPoint(x: 30, y: 5))
    shape(on: tail, path: spine, fill: nil, stroke: Design.pink, lineWidth: 4)
  }

  private func drawHead() {
    head.frame = Design.face
    addDetail(leftGills, to: head, frame: Design.gills)
    addDetail(rightGills, to: head, frame: Design.gills.offsetBy(dx: 76, dy: 0))
    drawGills(on: leftGills, direction: -1)
    drawGills(on: rightGills, direction: 1)
    oval(on: head, head.bounds, Design.pink, stroke: Design.outline)
    oval(on: head, CGRect(x: 17, y: 5, width: 44, height: 25), "FBDCD9")
    makeEyes(in: head, left: 25, right: 53, y: 28, color: "72526B")
    cheeks(on: head, centers: [CGPoint(x: 14, y: 18), CGPoint(x: 64, y: 18)], color: "E6A0B8")
    smile(on: head, center: CGPoint(x: 39, y: 17), width: 15, color: "A5738D")
  }

  private func drawGills(on layer: CALayer, direction: CGFloat) {
    let rootX: CGFloat = direction < 0 ? 25 : 3
    for (height, tip) in [(12.0, 1.0), (22.0, 22.0), (30.0, 43.0)] {
      let end = CGPoint(x: rootX + direction * 21, y: tip)
      let start = CGPoint(x: rootX, y: height)
      line(on: layer, points: [start, end], color: Design.gill, width: 6)
      for fraction in [0.45, 0.75] {
        let point = CGPoint(
          x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
        line(
          on: layer,
          points: [
            CGPoint(x: point.x - 2, y: point.y - 4), CGPoint(x: point.x + 2, y: point.y + 4),
          ], color: "EDABC5", width: 3)
      }
    }
  }
}
