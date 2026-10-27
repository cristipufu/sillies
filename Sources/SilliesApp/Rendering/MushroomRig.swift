import AppKit
import QuartzCore

@MainActor
final class MushroomRig: CharacterRig {
  let cap = CALayer()
  let wateringCan = CALayer()
  let seedling = CALayer()
  let droplets = CALayer()

  private enum Design {
    static let cream = "F6E5C4"
    static let outline = "A08468"
    static let capColor = "CB8271"
    static let body = CGRect(x: 39, y: 25, width: 50, height: 52)
    static let face = CGRect(x: 27, y: 48, width: 74, height: 75)
    static let cap = CGRect(x: -13, y: 33, width: 100, height: 40)
    static let boots = [
      CGRect(x: 38, y: 20, width: 22, height: 15), CGRect(x: 68, y: 20, width: 22, height: 15),
    ]
    static let arms = [
      CGRect(x: 29, y: 36, width: 15, height: 28), CGRect(x: 84, y: 36, width: 15, height: 28),
    ]
    static let can = CGRect(x: 88, y: 29, width: 30, height: 30)
    static let plant = CGRect(x: 68, y: 20, width: 20, height: 26)
    static let water = CGRect(x: 73, y: 31, width: 16, height: 19)
  }

  init() {
    super.init(gripFill: Design.cream, sleeveFill: Design.cream, gripOutline: Design.outline)
    oval(on: torso, Design.body, Design.cream, stroke: Design.outline)
    for (layer, frame) in zip([leftFoot, rightFoot], Design.boots) {
      softLimb(layer, frame: frame, fill: "879D78")
    }
    for (layer, frame) in zip([leftArm, rightArm], Design.arms) {
      softLimb(layer, frame: frame, fill: Design.cream)
    }
    drawHead()
    drawGarden()
  }

  private func drawHead() {
    head.frame = Design.face
    oval(on: head, CGRect(x: 13, y: 0, width: 48, height: 52), Design.cream, stroke: Design.outline)
    makeEyes(in: head, left: 26, right: 48, y: 24, color: "66574B")
    cheeks(on: head, centers: [CGPoint(x: 18, y: 15), CGPoint(x: 56, y: 15)], color: "E6B49A")
    smile(on: head, center: CGPoint(x: 37, y: 15), width: 12, color: Design.outline)
    addDetail(cap, to: head, frame: Design.cap)
    let dome = CGMutablePath()
    dome.move(to: CGPoint(x: 0, y: 8))
    dome.addCurve(
      to: CGPoint(x: 100, y: 8), control1: CGPoint(x: 11, y: 55), control2: CGPoint(x: 87, y: 49))
    dome.addQuadCurve(to: CGPoint(x: 0, y: 8), control: CGPoint(x: 50, y: -9))
    dome.closeSubpath()
    shape(on: cap, path: dome, fill: Design.capColor, stroke: "A76960")
    for spot in [
      CGRect(x: 17, y: 17, width: 15, height: 10), CGRect(x: 42, y: 25, width: 17, height: 11),
      CGRect(x: 70, y: 13, width: 14, height: 9),
    ] {
      oval(on: cap, spot, "F9EAD0")
    }
  }

  private func drawGarden() {
    addDetail(wateringCan, to: stage, frame: Design.can, restingOpacity: 0)
    pill(
      on: wateringCan, CGRect(x: 5, y: 3, width: 18, height: 17), "97B7AA", radius: 5,
      stroke: "698D80")
    let spout = CGMutablePath()
    spout.addLines(between: [
      CGPoint(x: 6, y: 8), CGPoint(x: -8, y: 18), CGPoint(x: -6, y: 23), CGPoint(x: 9, y: 15),
    ])
    spout.closeSubpath()
    shape(on: wateringCan, path: spout, fill: "97B7AA", stroke: "698D80")
    shape(
      on: wateringCan,
      path: CGPath(ellipseIn: CGRect(x: 19, y: 9, width: 11, height: 15), transform: nil),
      fill: nil, stroke: "698D80")
    addDetail(seedling, to: stage, frame: Design.plant, restingOpacity: 0)
    line(on: seedling, points: [CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 20)], color: "7C986B")
    oval(on: seedling, CGRect(x: 0, y: 12, width: 11, height: 7), "A7BC82")
    oval(on: seedling, CGRect(x: 10, y: 17, width: 10, height: 7), "8EAB72")
    addDetail(droplets, to: stage, frame: Design.water, restingOpacity: 0)
    for point in [CGPoint(x: 3, y: 1), CGPoint(x: 8, y: 7), CGPoint(x: 12, y: 14)] {
      oval(on: droplets, CGRect(x: point.x, y: point.y, width: 3, height: 5), "8FBBCD")
    }
  }
}
