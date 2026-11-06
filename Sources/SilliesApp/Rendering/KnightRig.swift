import AppKit
import QuartzCore

@MainActor
final class KnightRig: CharacterRig {
  let cape = CALayer()
  let visor = CALayer()
  let shield = CALayer()
  let shieldShine = CALayer()
  let polishingArm = CALayer()

  private enum Design {
    static let armor = "BDC9D5"
    static let highlight = "E6EDF1"
    static let outline = "8292A6"
    static let teal = "8EBDB6"
    static let ink = "455367"
    static let face = CGRect(x: 24, y: 57, width: 80, height: 64)
  }

  init() {
    super.init(gripFill: Design.armor, sleeveFill: Design.armor, gripOutline: Design.outline)
    drawCape()
    drawArmor()
    drawLimbs()
    drawHead()
    drawShield()
    drawPolishingArm()
  }

  private func drawCape() {
    accessory.frame = root.bounds
    let frame = CGRect(x: 22, y: 25, width: 84, height: 50)
    addDetail(cape, to: accessory, frame: frame)
    cape.anchorPoint = CGPoint(x: 0.5, y: 1)
    cape.position = CGPoint(x: frame.midX, y: frame.maxY)
    let cloth = CGMutablePath()
    cloth.move(to: CGPoint(x: 23, y: 48))
    cloth.addQuadCurve(to: CGPoint(x: 1, y: 4), control: CGPoint(x: 11, y: 22))
    cloth.addQuadCurve(to: CGPoint(x: 42, y: 2), control: CGPoint(x: 20, y: 9))
    cloth.addQuadCurve(to: CGPoint(x: 83, y: 4), control: CGPoint(x: 64, y: -2))
    cloth.addLine(to: CGPoint(x: 61, y: 48))
    cloth.closeSubpath()
    shape(on: cape, path: cloth, fill: Design.teal, stroke: "709B99")
    line(
      on: cape, points: [CGPoint(x: 12, y: 10), CGPoint(x: 27, y: 37)], color: "ACD0C6", width: 3)
  }

  private func drawArmor() {
    pill(
      on: torso, CGRect(x: 39, y: 26, width: 50, height: 47), Design.armor, radius: 17,
      stroke: Design.outline)
    pill(on: torso, CGRect(x: 47, y: 34, width: 34, height: 26), Design.highlight, radius: 11)
    pill(on: torso, CGRect(x: 39, y: 30, width: 50, height: 7), "A2B1C1", radius: 3)
    oval(on: torso, CGRect(x: 59, y: 54, width: 10, height: 10), "E8CCA0", stroke: "BAA17F")
  }

  private func drawLimbs() {
    for (foot, x) in [(leftFoot, 36.0), (rightFoot, 71.0)] {
      softLimb(foot, frame: CGRect(x: x, y: 20, width: 22, height: 16), fill: Design.armor)
      line(
        on: foot, points: [CGPoint(x: 4, y: 5), CGPoint(x: 18, y: 5)], color: Design.highlight,
        width: 3)
    }
    for (arm, x) in [(leftArm, 28.0), (rightArm, 84.0)] {
      softLimb(arm, frame: CGRect(x: x, y: 35, width: 16, height: 29), fill: Design.armor)
      arm.anchorPoint = CGPoint(x: 0.5, y: 1)
      arm.position = CGPoint(x: x + 8, y: 64)
      pill(on: arm, CGRect(x: 1, y: 17, width: 14, height: 11), Design.highlight, radius: 5)
      line(
        on: arm, points: [CGPoint(x: 3, y: 10), CGPoint(x: 13, y: 10)], color: Design.outline,
        width: 1.4)
    }
  }

  private func drawHead() {
    head.frame = Design.face
    pill(
      on: head, CGRect(x: 0, y: 0, width: 80, height: 62), Design.armor, radius: 29,
      stroke: Design.outline)
    let highlight = CGMutablePath()
    highlight.move(to: CGPoint(x: 12, y: 38))
    highlight.addQuadCurve(to: CGPoint(x: 33, y: 54), control: CGPoint(x: 14, y: 52))
    shape(on: head, path: highlight, fill: nil, stroke: Design.highlight, lineWidth: 4)
    line(
      on: head, points: [CGPoint(x: 40, y: 46), CGPoint(x: 40, y: 60)], color: Design.outline,
      width: 1.5)
    pill(
      on: head, CGRect(x: 9, y: 15, width: 62, height: 29), "F5E1C3", radius: 13,
      stroke: Design.outline)
    makeEyes(in: head, left: 27, right: 53, y: 30, color: Design.ink)
    cheeks(on: head, centers: [CGPoint(x: 18, y: 23), CGPoint(x: 62, y: 23)], color: "DFB3A5")
    smile(on: head, center: CGPoint(x: 40, y: 21), width: 10, color: "9E817C")
    addDetail(visor, to: head, frame: CGRect(x: 8, y: 40, width: 64, height: 12))
    pill(on: visor, visor.bounds, "ACBBCB", radius: 6, stroke: Design.outline)
    line(
      on: visor, points: [CGPoint(x: 10, y: 8), CGPoint(x: 54, y: 8)], color: Design.highlight,
      width: 2)
    for x in [3.0, 72.0] {
      oval(on: head, CGRect(x: x, y: 31, width: 6, height: 6), "D9C5A5", stroke: Design.outline)
    }
  }

  private func drawShield() {
    addDetail(shield, to: leftArm, frame: CGRect(x: -5, y: -2, width: 25, height: 28))
    let outline = CGMutablePath()
    outline.move(to: CGPoint(x: 2, y: 24))
    outline.addQuadCurve(to: CGPoint(x: 23, y: 24), control: CGPoint(x: 12.5, y: 30))
    outline.addQuadCurve(to: CGPoint(x: 12.5, y: 1), control: CGPoint(x: 25, y: 8))
    outline.addQuadCurve(to: CGPoint(x: 2, y: 24), control: CGPoint(x: 0, y: 8))
    outline.closeSubpath()
    shape(on: shield, path: outline, fill: Design.teal, stroke: Design.outline)
    line(
      on: shield, points: [CGPoint(x: 12.5, y: 8), CGPoint(x: 12.5, y: 22)], color: "DCE7CD",
      width: 2)
    line(
      on: shield, points: [CGPoint(x: 7, y: 17), CGPoint(x: 18, y: 17)], color: "DCE7CD", width: 2)
    addDetail(shieldShine, to: shield, frame: shield.bounds, restingOpacity: 0)
    line(
      on: shieldShine, points: [CGPoint(x: 5, y: 14), CGPoint(x: 14, y: 24)], color: "FFFAE2",
      width: 3)
  }

  private func drawPolishingArm() {
    addDetail(polishingArm, to: stage, frame: root.bounds, restingOpacity: 0)
    polishingArm.anchorPoint = CGPoint(x: 92 / 128.0, y: 59 / 128.0)
    polishingArm.position = CGPoint(x: 92, y: 59)
    let reach = CGMutablePath()
    reach.move(to: CGPoint(x: 92, y: 59))
    reach.addCurve(
      to: CGPoint(x: 44, y: 46), control1: CGPoint(x: 86, y: 27), control2: CGPoint(x: 57, y: 30))
    shape(on: polishingArm, path: reach, fill: nil, stroke: Design.outline, lineWidth: 12)
    shape(on: polishingArm, path: reach, fill: nil, stroke: Design.armor, lineWidth: 9)
    pill(
      on: polishingArm, CGRect(x: 34, y: 41, width: 16, height: 13), "F5E7C8", radius: 4,
      stroke: "C5B698")
    CharacterHandArtwork.draw(on: polishingArm, at: CGPoint(x: 39, y: 40), rig: self)
  }
}
