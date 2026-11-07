import AppKit
import QuartzCore

@MainActor
final class MimeRig: CharacterRig {
  let beret = CALayer()
  let scarf = CALayer()
  let reachingHands = CALayer()
  let contactMarks = CALayer()

  private enum Design {
    static let cream = "FFF2DB"
    static let ink = "51495D"
    static let outline = "8A7984"
    static let red = "CD7D85"
    static let glove = "FFFAED"
    static let face = CGRect(x: 31, y: 56, width: 66, height: 58)
  }

  init() {
    super.init(gripFill: Design.glove, sleeveFill: Design.cream, gripOutline: Design.outline)
    drawScarf()
    drawShirt()
    drawLimbs()
    drawFace()
    drawBeret()
    drawReachingHands()
  }

  private func drawScarf() {
    accessory.frame = root.bounds
    addDetail(scarf, to: accessory, frame: CGRect(x: 80, y: 39, width: 24, height: 29))
    scarf.anchorPoint = CGPoint(x: 0, y: 1)
    scarf.position = CGPoint(x: 80, y: 68)
    let cloth = CGMutablePath()
    cloth.move(to: CGPoint(x: 0, y: 28))
    cloth.addQuadCurve(to: CGPoint(x: 22, y: 2), control: CGPoint(x: 3, y: 8))
    cloth.addLine(to: CGPoint(x: 12, y: 5))
    cloth.addQuadCurve(to: CGPoint(x: 0, y: 22), control: CGPoint(x: 3, y: 9))
    cloth.closeSubpath()
    shape(on: scarf, path: cloth, fill: Design.red, stroke: "A85F72")
  }

  private func drawShirt() {
    pill(
      on: torso, CGRect(x: 41, y: 28, width: 46, height: 43), Design.cream, radius: 15,
      stroke: Design.outline)
    for y in [39.0, 49.0, 59.0] {
      pill(on: torso, CGRect(x: 43, y: y, width: 42, height: 5), Design.ink, radius: 2)
    }
    pill(on: torso, CGRect(x: 41, y: 26, width: 46, height: 11), Design.ink, radius: 5)
    for x in [50.0, 73.0] {
      line(
        on: torso, points: [CGPoint(x: x, y: 31), CGPoint(x: x, y: 64)], color: "AA727C", width: 3)
      oval(on: torso, CGRect(x: x - 2, y: 39, width: 4, height: 4), "E6C78D")
    }
  }

  private func drawLimbs() {
    for (foot, x) in [(leftFoot, 35.0), (rightFoot, 72.0)] {
      softLimb(foot, frame: CGRect(x: x, y: 20, width: 22, height: 15), fill: Design.ink)
      line(
        on: foot, points: [CGPoint(x: 5, y: 9), CGPoint(x: 13, y: 10)], color: "8B8198", width: 2)
    }
    for (arm, x) in [(leftArm, 28.0), (rightArm, 85.0)] {
      softLimb(arm, frame: CGRect(x: x, y: 35, width: 15, height: 28), fill: Design.cream)
      arm.anchorPoint = CGPoint(x: 0.5, y: 1)
      arm.position = CGPoint(x: x + 7.5, y: 63)
      for y in [14.0, 22.0] {
        pill(on: arm, CGRect(x: 0, y: y, width: 15, height: 4), Design.ink, radius: 1)
      }
      pill(
        on: arm, CGRect(x: -1, y: -2, width: 17, height: 13), Design.glove, radius: 6,
        stroke: Design.outline)
      for x in [5.0, 9.0] {
        line(
          on: arm, points: [CGPoint(x: x, y: 2), CGPoint(x: x, y: 6)], color: "CDC0BE", width: 1)
      }
    }
  }

  private func drawFace() {
    head.frame = Design.face
    pill(
      on: head, CGRect(x: 0, y: 5, width: 66, height: 52), Design.ink, radius: 24,
      stroke: Design.outline)
    oval(on: head, CGRect(x: 5, y: 1, width: 56, height: 48), Design.cream, stroke: Design.outline)
    makeEyes(in: head, left: 21, right: 45, y: 28, color: Design.ink)
    cheeks(on: head, centers: [CGPoint(x: 11, y: 18), CGPoint(x: 55, y: 18)], color: "E4ACA9")
    smile(on: head, center: CGPoint(x: 33, y: 14), width: 12, color: "B77B85")
    line(
      on: head, points: [CGPoint(x: 45, y: 19), CGPoint(x: 45, y: 16)], color: Design.ink,
      width: 1.5)
    line(
      on: head, points: [CGPoint(x: 17, y: 39), CGPoint(x: 24, y: 40)], color: Design.ink, width: 2)
    line(
      on: head, points: [CGPoint(x: 41, y: 40), CGPoint(x: 48, y: 39)], color: Design.ink, width: 2)
    pill(
      on: head, CGRect(x: 12, y: -3, width: 43, height: 8), Design.red, radius: 4, stroke: "A85F72")
  }

  private func drawBeret() {
    addDetail(beret, to: head, frame: CGRect(x: -4, y: 43, width: 77, height: 22))
    oval(on: beret, CGRect(x: 0, y: 3, width: 76, height: 18), Design.red, stroke: "A85F72")
    pill(on: beret, CGRect(x: 12, y: 1, width: 55, height: 7), "A85F72", radius: 3)
    line(
      on: beret, points: [CGPoint(x: 42, y: 18), CGPoint(x: 46, y: 23)], color: Design.ink, width: 3
    )
    line(
      on: beret, points: [CGPoint(x: 13, y: 14), CGPoint(x: 28, y: 17)], color: "E9A5A9", width: 2)
  }

  private func drawReachingHands() {
    addDetail(reachingHands, to: stage, frame: root.bounds, restingOpacity: 0)
    for (shoulder, elbow, palm) in [
      (CGPoint(x: 36, y: 60), CGPoint(x: 20, y: 68), CGPoint(x: 30, y: 87)),
      (CGPoint(x: 92, y: 60), CGPoint(x: 103, y: 65), CGPoint(x: 100, y: 81)),
    ] {
      let arm = CGMutablePath()
      arm.move(to: shoulder)
      arm.addQuadCurve(to: palm, control: elbow)
      shape(on: reachingHands, path: arm, fill: nil, stroke: Design.outline, lineWidth: 12)
      shape(on: reachingHands, path: arm, fill: nil, stroke: Design.cream, lineWidth: 9)
      pill(
        on: reachingHands, CGRect(x: palm.x - 7, y: palm.y - 3, width: 14, height: 18),
        Design.glove, radius: 6, stroke: Design.outline)
      for offset in [-2.0, 2.0] {
        line(
          on: reachingHands,
          points: [
            CGPoint(x: palm.x + offset, y: palm.y + 6), CGPoint(x: palm.x + offset, y: palm.y + 11),
          ], color: "C5B9BC", width: 1)
      }
    }
    addDetail(contactMarks, to: stage, frame: root.bounds, restingOpacity: 0)
    contactMarks.name = ArtworkHitTester.decorationName
    for x in [23.0, 100.0] {
      line(
        on: contactMarks, points: [CGPoint(x: x - 3, y: 106), CGPoint(x: x - 5, y: 110)],
        color: "B9B5CF", width: 1.5)
      line(
        on: contactMarks, points: [CGPoint(x: x + 5, y: 104), CGPoint(x: x + 8, y: 107)],
        color: "B9B5CF", width: 1.5)
    }
  }
}
