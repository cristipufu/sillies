import AppKit
import QuartzCore

/// Bloop has eight independently posed arms, all drawn once inside the small rig.
@MainActor
final class OctopusRig: CharacterRig {
  let rearArms = (0..<4).map { _ in CALayer() }

  private enum Design {
    static let coral = "EEA49F"
    static let pale = "FFD6BC"
    static let outline = "B67680"
    static let face = CGRect(x: 26, y: 48, width: 76, height: 65)
    static let rearFrames = [
      CGRect(x: 10, y: 26, width: 28, height: 40),
      CGRect(x: 32, y: 23, width: 28, height: 40),
      CGRect(x: 66, y: 23, width: 28, height: 40),
      CGRect(x: 90, y: 26, width: 28, height: 40),
    ]
    static let frontFrames = [
      CGRect(x: 39, y: 20, width: 24, height: 36),
      CGRect(x: 65, y: 20, width: 24, height: 36),
    ]
    static let sideFrames = [
      CGRect(x: 14, y: 44, width: 27, height: 31),
      CGRect(x: 87, y: 44, width: 27, height: 31),
    ]
    static let armOutlineWidth: CGFloat = 13
    static let armFillWidth: CGFloat = 9
  }

  init() {
    super.init(gripFill: Design.coral, sleeveFill: Design.coral, gripOutline: Design.outline)
    accessory.frame = root.bounds
    for (arm, frame) in zip(rearArms, Design.rearFrames) {
      addDetail(arm, to: accessory, frame: frame)
      drawArm(on: arm)
    }
    for (arm, frame) in zip([leftFoot, rightFoot], Design.frontFrames) {
      arm.frame = frame
      drawArm(on: arm)
    }
    for (arm, frame) in zip([leftArm, rightArm], Design.sideFrames) {
      arm.frame = frame
      drawArm(on: arm)
    }
    drawMantle()
    drawSuckers()
  }

  private func drawArm(on layer: CALayer) {
    let arm = CGMutablePath()
    arm.move(to: CGPoint(x: 12, y: 32))
    arm.addCurve(
      to: CGPoint(x: 18, y: 8), control1: CGPoint(x: 1, y: 15), control2: CGPoint(x: 2, y: 1))
    arm.addQuadCurve(to: CGPoint(x: 22, y: 15), control: CGPoint(x: 27, y: 8))
    shape(
      on: layer, path: arm, fill: nil, stroke: Design.outline, lineWidth: Design.armOutlineWidth)
    shape(on: layer, path: arm, fill: nil, stroke: Design.coral, lineWidth: Design.armFillWidth)
    for center in [CGPoint(x: 9, y: 12), CGPoint(x: 17, y: 8)] {
      oval(on: layer, CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4), Design.pale)
    }
  }

  private func drawMantle() {
    head.frame = Design.face
    oval(on: head, head.bounds, Design.coral, stroke: Design.outline)
    oval(on: head, CGRect(x: 15, y: 4, width: 46, height: 25), "F7B9AE")
    oval(on: head, CGRect(x: 15, y: 47, width: 18, height: 8), "FAD0C1")
    makeEyes(in: head, left: 25, right: 51, y: 29, color: "6F4858")
    cheeks(on: head, centers: [CGPoint(x: 14, y: 18), CGPoint(x: 62, y: 18)], color: "DF8791")
    smile(on: head, center: CGPoint(x: 38, y: 17), width: 14, color: "985D6E")
  }

  private func drawSuckers() {
    for (parent, y) in [(hangingArms, 99.0), (secondaryGrip, 75.0)] {
      for x in [108.0, 113.0] {
        oval(on: parent, CGRect(x: x, y: y, width: 4, height: 4), Design.pale)
      }
    }
  }
}
