import AppKit
import QuartzCore

/// Boo's scalloped sheet and shy fold share the crew's contact anchors.
@MainActor
final class GhostRig: CharacterRig {
  let sheetFold = CALayer()

  private enum Design {
    static let cream = "FFF7EA"
    static let shade = "DED6F0"
    static let outline = "A39AB9"
    static let face = CGRect(x: 27, y: 24, width: 74, height: 91)
    static let hands = [
      CGRect(x: 17, y: 47, width: 17, height: 25),
      CGRect(x: 94, y: 47, width: 17, height: 25),
    ]
    static let hem = [
      CGRect(x: 36, y: 20, width: 22, height: 15),
      CGRect(x: 70, y: 20, width: 22, height: 15),
    ]
    static let fold = CGRect(x: 10, y: 36, width: 54, height: 28)
  }

  init() {
    super.init(gripFill: Design.cream, sleeveFill: Design.cream, gripOutline: Design.outline)
    for (layer, frame) in zip([leftArm, rightArm], Design.hands) {
      softLimb(layer, frame: frame, fill: Design.cream)
    }
    for (layer, frame) in zip([leftFoot, rightFoot], Design.hem) {
      softLimb(layer, frame: frame, fill: Design.cream)
    }
    drawSheet()
    drawFace()
    drawFold()
  }

  private func drawSheet() {
    head.frame = Design.face
    let sheet = CGMutablePath()
    sheet.move(to: CGPoint(x: 0, y: 14))
    sheet.addLine(to: CGPoint(x: 4, y: 54))
    sheet.addCurve(
      to: CGPoint(x: 70, y: 54), control1: CGPoint(x: 1, y: 100), control2: CGPoint(x: 73, y: 100))
    sheet.addLine(to: CGPoint(x: 74, y: 14))
    for x in [74.0, 50, 26] {
      sheet.addQuadCurve(to: CGPoint(x: x - 12, y: 1), control: CGPoint(x: x - 2, y: -5))
      sheet.addQuadCurve(to: CGPoint(x: x - 24, y: 14), control: CGPoint(x: x - 22, y: 22))
    }
    sheet.closeSubpath()
    shape(on: head, path: sheet, fill: Design.cream, stroke: Design.outline)
    let fold = CGMutablePath()
    fold.move(to: CGPoint(x: 60, y: 67))
    fold.addQuadCurve(to: CGPoint(x: 64, y: 20), control: CGPoint(x: 69, y: 41))
    shape(on: head, path: fold, fill: nil, stroke: Design.shade, lineWidth: 5)
  }

  private func drawFace() {
    makeEyes(in: head, left: 24, right: 50, y: 52, color: "655B78")
    cheeks(on: head, centers: [CGPoint(x: 14, y: 41), CGPoint(x: 60, y: 41)], color: "EBC3CE")
    oval(on: head, CGRect(x: 34, y: 36, width: 6, height: 8), "8D7D9F")
  }

  private func drawFold() {
    addDetail(sheetFold, to: head, frame: Design.fold, restingOpacity: 0)
    pill(on: sheetFold, sheetFold.bounds, Design.shade, radius: 12, stroke: Design.outline)
    smile(on: sheetFold, center: CGPoint(x: 27, y: 19), width: 38, color: Design.cream)
  }
}
