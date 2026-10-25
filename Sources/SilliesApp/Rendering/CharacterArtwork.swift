import AppKit

@MainActor
final class CatRig: CharacterRig {
  init() {
    super.init()
    accessory.frame = root.bounds
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: 89, y: 37))
    tail.addCurve(
      to: CGPoint(x: 103, y: 67), control1: CGPoint(x: 117, y: 33), control2: CGPoint(x: 116, y: 64)
    )
    shape(on: accessory, path: tail, fill: nil, stroke: "D9965D", lineWidth: 13)
    oval(on: torso, CGRect(x: 35, y: 24, width: 57, height: 49), "F0BC83", stroke: "B77D55")
    oval(on: torso, CGRect(x: 45, y: 26, width: 36, height: 38), "FFE9C9")
    for (part, x) in [(leftFoot, 39.0), (rightFoot, 73.0)] {
      part.frame = CGRect(x: x, y: 20, width: 19, height: 17)
      pill(on: part, CGRect(x: 0, y: 0, width: 19, height: 15), "F8D4A5", stroke: "B77D55")
      line(on: part, points: [CGPoint(x: 7, y: 2), CGPoint(x: 7, y: 5)], color: "C08E66", width: 1)
      line(
        on: part, points: [CGPoint(x: 12, y: 2), CGPoint(x: 12, y: 5)], color: "C08E66", width: 1)
    }
    for (part, x) in [(leftArm, 34.0), (rightArm, 80.0)] {
      part.frame = CGRect(x: x, y: 34, width: 14, height: 25)
      pill(on: part, CGRect(x: 0, y: 0, width: 14, height: 25), "F3C38F", stroke: "B77D55")
    }
    head.frame = CGRect(x: 20, y: 56, width: 88, height: 64)
    let ears = CGMutablePath()
    ears.move(to: CGPoint(x: 6, y: 32))
    ears.addLine(to: CGPoint(x: 7, y: 61))
    ears.addQuadCurve(to: CGPoint(x: 32, y: 49), control: CGPoint(x: 13, y: 65))
    ears.closeSubpath()
    ears.move(to: CGPoint(x: 56, y: 49))
    ears.addLine(to: CGPoint(x: 78, y: 62))
    ears.addQuadCurve(to: CGPoint(x: 82, y: 31), control: CGPoint(x: 85, y: 62))
    ears.closeSubpath()
    shape(on: head, path: ears, fill: "F0BC83", stroke: "B77D55")
    for points in [
      [CGPoint(x: 12, y: 43), CGPoint(x: 13, y: 56), CGPoint(x: 26, y: 47)],
      [CGPoint(x: 63, y: 47), CGPoint(x: 77, y: 56), CGPoint(x: 77, y: 42)],
    ] {
      let path = CGMutablePath()
      path.addLines(between: points)
      path.closeSubpath()
      shape(on: head, path: path, fill: "EAA696")
    }
    oval(on: head, CGRect(x: 0, y: 3, width: 88, height: 53), "F6CA97", stroke: "B77D55")
    oval(on: head, CGRect(x: 19, y: 10, width: 50, height: 28), "FFE9CC")
    for x in [35.0, 44.0, 53.0] {
      pill(on: head, CGRect(x: x - 2, y: 43, width: 4, height: x == 44 ? 9 : 7), "D89D69")
    }
    makeEyes(in: head, left: 28, right: 60, y: 31)
    oval(on: head, CGRect(x: 14, y: 22, width: 11, height: 5), "EAA99A")
    oval(on: head, CGRect(x: 64, y: 22, width: 11, height: 5), "EAA99A")
    let nose = CGMutablePath()
    nose.addLines(between: [CGPoint(x: 40, y: 24), CGPoint(x: 48, y: 24), CGPoint(x: 44, y: 20)])
    nose.closeSubpath()
    shape(on: head, path: nose, fill: "9D655B")
    let mouth = CGMutablePath()
    mouth.move(to: CGPoint(x: 44, y: 20))
    mouth.addQuadCurve(to: CGPoint(x: 37, y: 17), control: CGPoint(x: 43, y: 13))
    mouth.move(to: CGPoint(x: 44, y: 20))
    mouth.addQuadCurve(to: CGPoint(x: 51, y: 17), control: CGPoint(x: 45, y: 13))
    shape(on: head, path: mouth, fill: nil, stroke: "9D655B", lineWidth: 1.6)
    for side in [-1.0, 1.0] {
      let x = side < 0 ? 16.0 : 72.0
      for offset in [-3.0, 3.0] {
        line(
          on: head,
          points: [CGPoint(x: x, y: 20 + offset), CGPoint(x: x + side * 12, y: 21 + offset * 1.7)],
          color: "BA8A68", width: 1.2)
      }
    }
    pill(on: torso, CGRect(x: 40, y: 57, width: 49, height: 9), "D98178")
    let scarf = CGMutablePath()
    scarf.addLines(between: [
      CGPoint(x: 75, y: 61), CGPoint(x: 88, y: 59), CGPoint(x: 93, y: 43), CGPoint(x: 81, y: 46),
    ])
    scarf.closeSubpath()
    shape(on: torso, path: scarf, fill: "D98178")
  }
}

@MainActor
final class NinjaRig: CharacterRig {
  init() {
    super.init(gripFill: "F2D8B9", sleeveFill: "48425F", gripOutline: "292639")
    accessory.frame = root.bounds
    line(
      on: accessory, points: [CGPoint(x: 80, y: 31), CGPoint(x: 100, y: 86)], color: "504B69",
      width: 9)
    line(
      on: accessory, points: [CGPoint(x: 97, y: 78), CGPoint(x: 103, y: 95)], color: "A5A0C3",
      width: 7)
    line(
      on: accessory, points: [CGPoint(x: 91, y: 78), CGPoint(x: 105, y: 83)], color: "C9C2E3",
      width: 4)
    let ties = CGMutablePath()
    ties.addLines(between: [
      CGPoint(x: 98, y: 99), CGPoint(x: 119, y: 103), CGPoint(x: 112, y: 92),
      CGPoint(x: 121, y: 84), CGPoint(x: 98, y: 88),
    ])
    ties.closeSubpath()
    shape(on: accessory, path: ties, fill: "AAA2E6", stroke: "79719F", lineWidth: 1.5)
    pill(
      on: torso, CGRect(x: 37, y: 25, width: 54, height: 47), "3E3A57", radius: 18, stroke: "292639"
    )
    pill(on: torso, CGRect(x: 45, y: 31, width: 14, height: 33), "4D4868", radius: 7)
    for (part, x) in [(leftFoot, 38.0), (rightFoot, 74.0)] {
      part.frame = CGRect(x: x, y: 20, width: 21, height: 15)
      pill(on: part, CGRect(x: 0, y: 0, width: 21, height: 15), "363247", stroke: "292639")
      line(
        on: part, points: [CGPoint(x: 4, y: 5), CGPoint(x: 17, y: 5)], color: "6C658A", width: 2)
    }
    for (part, x) in [(leftArm, 29.0), (rightArm, 85.0)] {
      part.frame = CGRect(x: x, y: 38, width: 15, height: 27)
      pill(on: part, CGRect(x: 0, y: 0, width: 15, height: 27), "48425F", stroke: "292639")
      pill(on: part, CGRect(x: 1, y: 0, width: 13, height: 10), "F2D8B9")
      pill(on: part, CGRect(x: 0, y: 10, width: 15, height: 5), "AAA2E6")
    }
    head.frame = CGRect(x: 21, y: 57, width: 86, height: 63)
    oval(on: head, CGRect(x: 0, y: 0, width: 86, height: 61), "3E3A57", stroke: "292639")
    let sheen = CGMutablePath()
    sheen.move(to: CGPoint(x: 12, y: 38))
    sheen.addQuadCurve(to: CGPoint(x: 35, y: 55), control: CGPoint(x: 13, y: 52))
    shape(on: head, path: sheen, fill: nil, stroke: "57516F", lineWidth: 4)
    pill(on: head, CGRect(x: 10, y: 14, width: 66, height: 28), "F5E0C5", stroke: "292639")
    pill(on: head, CGRect(x: 4, y: 42, width: 78, height: 12), "AAA2E6", radius: 5)
    pill(on: head, CGRect(x: 5, y: 48, width: 76, height: 3), "C4BEF2", radius: 1)
    let emblem = CGMutablePath()
    emblem.addLines(between: [
      CGPoint(x: 43, y: 44), CGPoint(x: 47, y: 48), CGPoint(x: 43, y: 52), CGPoint(x: 39, y: 48),
    ])
    emblem.closeSubpath()
    shape(on: head, path: emblem, fill: "F8F3E9")
    makeEyes(in: head, left: 29, right: 57, y: 28, color: "393345")
    line(
      on: head, points: [CGPoint(x: 23, y: 36), CGPoint(x: 32, y: 35)], color: "6D5761", width: 1.5)
    line(
      on: head, points: [CGPoint(x: 54, y: 35), CGPoint(x: 63, y: 36)], color: "6D5761", width: 1.5)
    pill(on: torso, CGRect(x: 36, y: 38, width: 56, height: 8), "AAA2E6", radius: 2)
    pill(on: torso, CGRect(x: 61, y: 34, width: 8, height: 16), "C5BEED", radius: 2)
  }
}
