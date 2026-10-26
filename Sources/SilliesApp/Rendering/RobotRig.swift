import AppKit
import QuartzCore

/// Bolt keeps the shared attachment anchors; the face display and antenna are local details.
@MainActor
final class RobotRig: CharacterRig {
  let antenna = CALayer()
  let viewfinder = CALayer()
  private static let outline = "7C96A5"

  init() {
    super.init(gripFill: "A9CADB", sleeveFill: "DAE4E6", gripOutline: Self.outline)
    drawBody()
    drawLegs()
    drawArms()
    drawHead()
    drawAntenna()
    drawViewfinder()
    drawMagneticGrips()
  }

  private func drawBody() {
    pill(
      on: torso, CGRect(x: 40, y: 28, width: 48, height: 42), "F1EFE4", radius: 11,
      stroke: Self.outline)
    pill(on: torso, CGRect(x: 48, y: 35, width: 32, height: 25), "BCD5DF", radius: 6)
    pill(on: torso, CGRect(x: 57, y: 61, width: 14, height: 8), "9FB8C4", radius: 3)
    oval(on: torso, CGRect(x: 54, y: 45, width: 7, height: 7), "F4C478")
    for y in [43.0, 48.0] {
      line(
        on: torso, points: [CGPoint(x: 66, y: y), CGPoint(x: 74, y: y)],
        color: Self.outline, width: 1.5)
    }
  }

  private func drawLegs() {
    for (part, x) in [(leftFoot, 39.0), (rightFoot, 70.0)] {
      part.frame = CGRect(x: x, y: 20, width: 20, height: 22)
      part.anchorPoint = CGPoint(x: 0.5, y: 0)
      part.position = CGPoint(x: x + 10, y: 20)
      pill(on: part, CGRect(x: 6, y: 7, width: 9, height: 15), "9FB8C4", radius: 3)
      line(
        on: part, points: [CGPoint(x: 7, y: 14), CGPoint(x: 14, y: 14)],
        color: "E4EDF0", width: 2)
      pill(
        on: part, CGRect(x: 0, y: 0, width: 20, height: 12), "A9CADB", radius: 5,
        stroke: Self.outline)
      line(
        on: part, points: [CGPoint(x: 4, y: 3), CGPoint(x: 16, y: 3)],
        color: "DBE8ED", width: 1.5)
    }
  }

  private func drawArms() {
    for (part, x) in [(leftArm, 28.0), (rightArm, 85.0)] {
      part.frame = CGRect(x: x, y: 37, width: 15, height: 27)
      pill(
        on: part, CGRect(x: 2, y: 8, width: 11, height: 19), "DAE4E6", radius: 5,
        stroke: Self.outline)
      pill(
        on: part, CGRect(x: 0, y: 0, width: 15, height: 13), "A9CADB", radius: 5,
        stroke: Self.outline)
      line(
        on: part, points: [CGPoint(x: 5, y: 3), CGPoint(x: 5, y: 7)],
        color: Self.outline, width: 1)
    }
  }

  private func drawHead() {
    head.frame = CGRect(x: 24, y: 58, width: 80, height: 65)
    for x in [-5.0, 76.0] {
      pill(
        on: head, CGRect(x: x, y: 17, width: 9, height: 23), "A9CADB", radius: 4,
        stroke: Self.outline)
    }
    pill(
      on: head, CGRect(x: 0, y: 1, width: 80, height: 53), "F1EFE4", radius: 15,
      stroke: Self.outline)
    line(
      on: head, points: [CGPoint(x: 16, y: 48), CGPoint(x: 61, y: 48)],
      color: "FFFFFF", width: 3)
    pill(
      on: head, CGRect(x: 8, y: 10, width: 64, height: 33), "293F50", radius: 10,
      stroke: "627D8D")
    eyes.frame = head.bounds
    closedEyes.frame = head.bounds
    head.addSublayer(eyes)
    head.addSublayer(closedEyes)
    for x in [21.0, 49.0] {
      pill(on: eyes, CGRect(x: x, y: 22, width: 10, height: 14), "8ADBE4", radius: 4)
      pill(on: eyes, CGRect(x: x + 2, y: 30, width: 5, height: 3), "DBFBF6", radius: 1)
      line(
        on: closedEyes,
        points: [
          CGPoint(x: x, y: 28), CGPoint(x: x + 5, y: 31),
          CGPoint(x: x + 10, y: 28),
        ], color: "8ADBE4", width: 2.5)
    }
    pill(on: head, CGRect(x: 35, y: 15, width: 10, height: 2), "8ADBE4", radius: 1)
    closedEyes.opacity = 0
  }

  private func drawAntenna() {
    antenna.frame = CGRect(x: 39, y: 53, width: 18, height: 14)
    antenna.anchorPoint = CGPoint(x: 0, y: 0)
    antenna.position = CGPoint(x: 39, y: 53)
    head.addSublayer(antenna)
    line(
      on: antenna, points: [CGPoint(x: 1, y: 0), CGPoint(x: 3, y: 8), CGPoint(x: 10, y: 10)],
      color: Self.outline, width: 2.5)
    oval(on: antenna, CGRect(x: 8, y: 7, width: 7, height: 7), "E9A591", stroke: Self.outline)
    oval(on: antenna, CGRect(x: 10, y: 11, width: 2, height: 2), "FFE6CD")
  }

  private func drawViewfinder() {
    viewfinder.frame = head.bounds
    head.addSublayer(viewfinder)
    for (x, dx) in [(16.0, 1.0), (64.0, -1.0)] {
      for (y, dy) in [(17.0, 1.0), (37.0, -1.0)] {
        line(
          on: viewfinder,
          points: [
            CGPoint(x: x, y: y + dy * 5), CGPoint(x: x, y: y),
            CGPoint(x: x + dx * 7, y: y),
          ], color: "A7F1E5", width: 2)
      }
    }
    oval(on: viewfinder, CGRect(x: 37, y: 24, width: 6, height: 6), "F4C478")
    viewfinder.opacity = 0
  }

  private func drawMagneticGrips() {
    for (parent, y) in [(hangingArms, 96.0), (secondaryGrip, 72.0)] {
      pill(on: parent, CGRect(x: 113, y: y + 1, width: 4, height: 9), "D7E9EF", radius: 2)
    }
  }

  override func resetBehaviorPose() {
    super.resetBehaviorPose()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    antenna.removeAllAnimations()
    viewfinder.removeAllAnimations()
    antenna.transform = CATransform3DIdentity
    viewfinder.transform = CATransform3DIdentity
    viewfinder.opacity = 0
    CATransaction.commit()
  }
}
