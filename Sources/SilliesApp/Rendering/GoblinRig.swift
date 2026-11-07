import AppKit
import QuartzCore

@MainActor
final class GoblinRig: CharacterRig {
  let leftEar = CALayer()
  let rightEar = CALayer()
  let goggles = CALayer()
  let gadget = CALayer()
  let gadgetNeedle = CALayer()
  let steam = CALayer()

  private enum Design {
    static let skin = "AFC794"
    static let outline = "748866"
    static let plum = "8D789C"
    static let darkPlum = "665871"
    static let copper = "C79D70"
    static let face = CGRect(x: 28, y: 55, width: 72, height: 59)
  }

  init() {
    super.init(gripFill: Design.skin, sleeveFill: Design.plum, gripOutline: Design.outline)
    drawOveralls()
    drawLimbs()
    drawHead()
    drawGoggles()
    drawGadget()
    drawSteam()
  }

  private func drawOveralls() {
    pill(
      on: torso, CGRect(x: 40, y: 26, width: 48, height: 45), Design.plum, radius: 16,
      stroke: Design.darkPlum)
    pill(on: torso, CGRect(x: 48, y: 44, width: 32, height: 23), "C5B2CA", radius: 8)
    for x in [46.0, 76.0] {
      pill(on: torso, CGRect(x: x, y: 49, width: 6, height: 23), Design.plum, radius: 3)
      oval(on: torso, CGRect(x: x, y: 48, width: 6, height: 6), Design.copper)
    }
    pill(
      on: torso, CGRect(x: 54, y: 34, width: 21, height: 13), "AE97B7", radius: 4,
      stroke: Design.darkPlum)
    line(
      on: torso, points: [CGPoint(x: 59, y: 45), CGPoint(x: 59, y: 52)], color: Design.copper,
      width: 3)
    pill(on: torso, CGRect(x: 75, y: 29, width: 8, height: 10), "D6BF8E", radius: 2)
  }

  private func drawLimbs() {
    for (foot, x) in [(leftFoot, 36.0), (rightFoot, 71.0)] {
      softLimb(foot, frame: CGRect(x: x, y: 20, width: 22, height: 15), fill: Design.darkPlum)
      line(
        on: foot, points: [CGPoint(x: 5, y: 8), CGPoint(x: 16, y: 8)], color: "AD94AA", width: 2)
    }
    for (arm, x) in [(leftArm, 28.0), (rightArm, 85.0)] {
      softLimb(arm, frame: CGRect(x: x, y: 35, width: 15, height: 28), fill: Design.plum)
      arm.anchorPoint = CGPoint(x: 0.5, y: 1)
      arm.position = CGPoint(x: x + 7.5, y: 63)
      pill(
        on: arm, CGRect(x: 0, y: 0, width: 15, height: 11), Design.skin, radius: 6,
        stroke: Design.outline)
      pill(on: arm, CGRect(x: -1, y: 11, width: 17, height: 5), "B39FC0", radius: 2)
    }
  }

  private func drawHead() {
    head.frame = Design.face
    drawEar(leftEar, frame: CGRect(x: -19, y: 21, width: 30, height: 31))
    drawEar(rightEar, frame: CGRect(x: 61, y: 21, width: 30, height: 31))
    for detail in rightEar.sublayers ?? [] {
      detail.setAffineTransform(CGAffineTransform(translationX: 30, y: 0).scaledBy(x: -1, y: 1))
    }
    pill(
      on: head, CGRect(x: 0, y: 1, width: 72, height: 56), Design.skin, radius: 25,
      stroke: Design.outline)
    oval(on: head, CGRect(x: 5, y: 6, width: 62, height: 33), "BFD5A4")
    makeEyes(in: head, left: 23, right: 49, y: 30, color: "4F5147")
    cheeks(on: head, centers: [CGPoint(x: 13, y: 19), CGPoint(x: 59, y: 19)], color: "D6AD91")
    oval(on: head, CGRect(x: 30, y: 21, width: 13, height: 9), "91AE7A")
    smile(on: head, center: CGPoint(x: 36, y: 14), width: 17, color: "6D805D")
    pill(on: head, CGRect(x: 40, y: 10, width: 5, height: 7), "FFF1D5", radius: 1.8)
    for x in [10.0, 15, 56, 61] {
      oval(on: head, CGRect(x: x, y: 25, width: 2, height: 2), Design.outline)
    }
  }

  private func drawEar(_ ear: CALayer, frame: CGRect) {
    addDetail(ear, to: head, frame: frame)
    let outline = CGMutablePath()
    outline.move(to: CGPoint(x: 29, y: 8))
    outline.addQuadCurve(to: CGPoint(x: 2, y: 29), control: CGPoint(x: 10, y: 10))
    outline.addQuadCurve(to: CGPoint(x: 25, y: 0), control: CGPoint(x: 0, y: 0))
    outline.closeSubpath()
    shape(on: ear, path: outline, fill: Design.skin, stroke: Design.outline)
    line(on: ear, points: [CGPoint(x: 8, y: 20), CGPoint(x: 21, y: 8)], color: "D4B99C", width: 5)
  }

  private func drawGoggles() {
    addDetail(goggles, to: head, frame: CGRect(x: 7, y: 42, width: 58, height: 18))
    pill(on: goggles, CGRect(x: 0, y: 5, width: 58, height: 8), Design.darkPlum, radius: 3)
    for x in [7.0, 34.0] {
      oval(on: goggles, CGRect(x: x, y: 0, width: 19, height: 18), Design.copper, stroke: "917557")
      oval(on: goggles, CGRect(x: x + 3, y: 3, width: 13, height: 12), "C7E3DC")
      line(
        on: goggles, points: [CGPoint(x: x + 6, y: 11), CGPoint(x: x + 10, y: 14)], color: "F5F8ED",
        width: 2)
    }
  }

  private func drawGadget() {
    addDetail(
      gadget, to: stage, frame: CGRect(x: 44, y: 39, width: 40, height: 25), restingOpacity: 0)
    pill(on: gadget, gadget.bounds, Design.copper, radius: 7, stroke: "917557")
    oval(on: gadget, CGRect(x: 5, y: 5, width: 16, height: 16), "F4E5BC", stroke: "917557")
    addDetail(gadgetNeedle, to: gadget, frame: CGRect(x: 5, y: 5, width: 16, height: 16))
    line(
      on: gadgetNeedle, points: [CGPoint(x: 8, y: 8), CGPoint(x: 11, y: 13)],
      color: Design.darkPlum, width: 2)
    oval(on: gadget, CGRect(x: 27, y: 9, width: 7, height: 7), "AFC794", stroke: "748866")
    line(
      on: gadget, points: [CGPoint(x: 26, y: 20), CGPoint(x: 31, y: 28)], color: "917557", width: 3)
  }

  private func drawSteam() {
    addDetail(
      steam, to: stage, frame: CGRect(x: 84, y: 67, width: 24, height: 27), restingOpacity: 0)
    steam.name = ArtworkHitTester.decorationName
    for frame in [
      CGRect(x: 0, y: 0, width: 12, height: 12), CGRect(x: 6, y: 7, width: 14, height: 14),
      CGRect(x: 13, y: 17, width: 10, height: 10),
    ] {
      oval(on: steam, frame, "CEC9D3")
    }
  }
}
