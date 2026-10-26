import AppKit

/// Pogo's broad silhouette, raised eyes, webbed toes, and very important snack pouch.
@MainActor
final class FrogRig: CharacterRig {
  private static let outline = "648657"

  init() {
    super.init(gripFill: "B6D789", sleeveFill: "A2C879", gripOutline: Self.outline)
    drawBody()
    drawFeet()
    drawArms()
    drawHead()
    drawPouch()
    addStickyFingertips()
  }

  private func drawBody() {
    oval(on: torso, CGRect(x: 32, y: 25, width: 64, height: 46), "A2C879", stroke: Self.outline)
    oval(on: torso, CGRect(x: 43, y: 28, width: 42, height: 35), "F5EBC4")
    line(
      on: torso, points: [CGPoint(x: 49, y: 65), CGPoint(x: 87, y: 41)],
      color: "AA8C50", width: 4)
  }

  private func drawFeet() {
    for (part, x) in [(leftFoot, 28.0), (rightFoot, 71.0)] {
      part.frame = CGRect(x: x, y: 20, width: 29, height: 19)
      let web = CGMutablePath()
      web.move(to: CGPoint(x: 5, y: 1))
      web.addQuadCurve(to: CGPoint(x: 1, y: 8), control: CGPoint(x: -2, y: 1))
      web.addLine(to: CGPoint(x: 7, y: 16))
      web.addQuadCurve(to: CGPoint(x: 15, y: 14), control: CGPoint(x: 11, y: 21))
      web.addQuadCurve(to: CGPoint(x: 25, y: 13), control: CGPoint(x: 24, y: 19))
      web.addQuadCurve(to: CGPoint(x: 27, y: 3), control: CGPoint(x: 33, y: 5))
      web.closeSubpath()
      shape(on: part, path: web, fill: "BDD990", stroke: Self.outline)
      for toe in [10.0, 19.0] {
        line(
          on: part, points: [CGPoint(x: toe, y: 4), CGPoint(x: toe + 1, y: 9)],
          color: "8EB367", width: 1.3)
      }
    }
  }

  private func drawArms() {
    for (part, x) in [(leftArm, 26.0), (rightArm, 85.0)] {
      part.frame = CGRect(x: x, y: 36, width: 17, height: 27)
      pill(on: part, CGRect(x: 3, y: 6, width: 12, height: 21), "A2C879", stroke: Self.outline)
      oval(on: part, CGRect(x: 0, y: 0, width: 17, height: 13), "B6D789", stroke: Self.outline)
      for finger in [3.0, 8.0, 13.0] {
        oval(on: part, CGRect(x: finger - 2, y: -1, width: 5, height: 5), "C8E4A2")
      }
    }
  }

  private func drawHead() {
    head.frame = CGRect(x: 18, y: 57, width: 92, height: 64)
    for x in [5.0, 55.0] {
      oval(on: head, CGRect(x: x, y: 31, width: 32, height: 32), "B2D68B", stroke: Self.outline)
    }
    oval(on: head, CGRect(x: 0, y: 0, width: 92, height: 49), "B2D68B", stroke: Self.outline)
    oval(on: head, CGRect(x: 15, y: 6, width: 62, height: 23), "BEDD98")
    for x in [10.0, 60.0] {
      oval(on: head, CGRect(x: x, y: 37, width: 22, height: 23), "FFF7DF")
    }
    makeEyes(in: head, left: 21, right: 71, y: 48, color: "354A36")
    for x in [10.0, 70.0] {
      oval(on: head, CGRect(x: x, y: 18, width: 12, height: 6), "E7ACA1")
    }
    let smile = CGMutablePath()
    smile.move(to: CGPoint(x: 29, y: 23))
    smile.addQuadCurve(to: CGPoint(x: 63, y: 23), control: CGPoint(x: 46, y: 9))
    shape(on: head, path: smile, fill: nil, stroke: Self.outline, lineWidth: 2.2)
    for x in [39.0, 51.0] {
      oval(on: head, CGRect(x: x, y: 30, width: 2.5, height: 2), "7EA564")
    }
  }

  private func drawPouch() {
    stage.insertSublayer(accessory, below: head)
    accessory.frame = CGRect(x: 77, y: 36, width: 20, height: 23)
    pill(
      on: accessory, CGRect(x: 0, y: 0, width: 20, height: 21), "E9C66C", radius: 6,
      stroke: "AA8C50")
    pill(on: accessory, CGRect(x: 1, y: 12, width: 18, height: 9), "F6DB8A", radius: 4)
    oval(on: accessory, CGRect(x: 8, y: 9, width: 4, height: 4), "AA8C50")
  }

  private func addStickyFingertips() {
    for (parent, y) in [(hangingArms, 96.0), (secondaryGrip, 72.0)] {
      for offset in [2.0, 6.0, 10.0] {
        oval(
          on: parent, CGRect(x: 112, y: y + offset - 2, width: 5, height: 4), "D4EAAF")
      }
    }
  }
}
