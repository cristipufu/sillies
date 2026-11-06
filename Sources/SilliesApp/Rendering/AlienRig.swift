import AppKit
import QuartzCore

@MainActor
final class AlienRig: CharacterRig {
  let leftAntenna = CALayer()
  let rightAntenna = CALayer()
  let notebook = CALayer()
  let pencil = CALayer()
  let scanGlow = CALayer()

  private enum Design {
    static let skin = "B7BCE9"
    static let outline = "7C81AD"
    static let suit = "F1BFA7"
    static let suitOutline = "B98C82"
    static let ink = "393B58"
    static let body = CGRect(x: 39, y: 26, width: 50, height: 45)
    static let face = CGRect(x: 24, y: 62, width: 80, height: 49)
  }

  init() {
    super.init(gripFill: Design.skin, sleeveFill: Design.suit, gripOutline: Design.outline)
    drawSuit()
    drawLimbs()
    drawHead()
    drawFieldKit()
  }

  private func drawSuit() {
    pill(on: torso, Design.body, Design.suit, radius: 19, stroke: Design.suitOutline)
    pill(on: torso, CGRect(x: 48, y: 29, width: 32, height: 32), "FFE3CD", radius: 12)
    pill(on: torso, CGRect(x: 42, y: 59, width: 44, height: 9), "E5A78F", radius: 4)
    line(on: torso, points: [CGPoint(x: 64, y: 31), CGPoint(x: 64, y: 56)], color: "D5A28F")
    oval(on: torso, CGRect(x: 71, y: 46, width: 9, height: 9), "A3BCC3", stroke: "839EA7")
    oval(on: torso, CGRect(x: 74, y: 49, width: 3, height: 3), "FFF4D8")
  }

  private func drawLimbs() {
    for (foot, x) in [(leftFoot, 39.0), (rightFoot, 70.0)] {
      softLimb(foot, frame: CGRect(x: x, y: 20, width: 20, height: 15), fill: Design.skin)
      pill(on: foot, CGRect(x: 2, y: 2, width: 16, height: 4), "D3D6F2", radius: 2)
    }
    for (arm, x) in [(leftArm, 30.0), (rightArm, 83.0)] {
      softLimb(arm, frame: CGRect(x: x, y: 35, width: 15, height: 26), fill: Design.suit)
      pill(on: arm, CGRect(x: 1, y: 0, width: 13, height: 11), Design.skin, stroke: Design.outline)
      pill(on: arm, CGRect(x: 1, y: 10, width: 13, height: 4), "FFE3CD", radius: 2)
    }
  }

  private func drawHead() {
    head.frame = Design.face
    drawAntenna(leftAntenna, frame: CGRect(x: 14, y: 39, width: 18, height: 24))
    drawAntenna(rightAntenna, frame: CGRect(x: 51, y: 40, width: 18, height: 17))
    oval(on: head, head.bounds, Design.skin, stroke: Design.outline)
    oval(on: head, CGRect(x: 13, y: 30, width: 22, height: 9), "D3D7F4")
    eyes.frame = head.bounds
    closedEyes.frame = head.bounds
    head.addSublayer(eyes)
    head.addSublayer(closedEyes)
    closedEyes.opacity = 0
    for x in [18.0, 48.0] {
      oval(on: eyes, CGRect(x: x, y: 15, width: 14, height: 21), Design.ink)
      oval(on: eyes, CGRect(x: x + 3, y: 28, width: 4, height: 5), "FBFAFF")
      oval(on: eyes, CGRect(x: x + 8, y: 18, width: 2, height: 2), "9C9ECA")
      smile(on: closedEyes, center: CGPoint(x: x + 7, y: 24), width: 12, color: Design.ink)
    }
    cheeks(on: head, centers: [CGPoint(x: 11, y: 13), CGPoint(x: 69, y: 13)], color: "DDA7C2")
    smile(on: head, center: CGPoint(x: 40, y: 10), width: 10, color: Design.ink)
  }

  private func drawAntenna(_ antenna: CALayer, frame: CGRect) {
    addDetail(antenna, to: head, frame: frame)
    antenna.anchorPoint = CGPoint(x: 0.5, y: 0)
    antenna.position = CGPoint(x: frame.midX, y: frame.minY)
    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: 9, y: 0))
    stem.addQuadCurve(to: CGPoint(x: 5, y: frame.height - 5), control: CGPoint(x: 13, y: 15))
    shape(on: antenna, path: stem, fill: nil, stroke: Design.outline, lineWidth: 3)
    oval(
      on: antenna, CGRect(x: 1, y: frame.height - 9, width: 9, height: 9), "D7C8ED",
      stroke: Design.outline)
    oval(on: antenna, CGRect(x: 3, y: frame.height - 5, width: 3, height: 3), "F5E8FF")
  }

  private func drawFieldKit() {
    addDetail(
      notebook, to: stage, frame: CGRect(x: 80, y: 34, width: 24, height: 29), restingOpacity: 0)
    pill(on: notebook, notebook.bounds, "EDF0DB", radius: 4, stroke: "8D9D9B")
    pill(on: notebook, CGRect(x: 0, y: 0, width: 5, height: 29), "8D9D9B", radius: 2)
    for y in [9.0, 15.0, 21.0] {
      line(
        on: notebook, points: [CGPoint(x: 9, y: y), CGPoint(x: 19, y: y)], color: "ACB9AD",
        width: 1.4)
    }
    addDetail(
      pencil, to: stage, frame: CGRect(x: 100, y: 43, width: 4, height: 17), restingOpacity: 0)
    pill(on: pencil, pencil.bounds, "7C81AD", radius: 2)
    addDetail(
      scanGlow, to: stage, frame: CGRect(x: 94, y: 59, width: 27, height: 34), restingOpacity: 0)
    scanGlow.name = ArtworkHitTester.decorationName
    let beam = CGMutablePath()
    beam.addLines(between: [CGPoint(x: 0, y: 17), CGPoint(x: 24, y: 33), CGPoint(x: 24, y: 1)])
    beam.closeSubpath()
    shape(on: scanGlow, path: beam, fill: "95C9C7", opacity: 0.3)
    line(
      on: scanGlow, points: [CGPoint(x: 24, y: 1), CGPoint(x: 24, y: 33)], color: "80B9B6", width: 2
    )
  }
}
