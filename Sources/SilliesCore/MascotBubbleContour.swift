import CoreGraphics

/// A shared curved speech contour in local coordinates. Bottom tails use the minimum-y edge.
public enum MascotBubbleContour {
  public enum Tail: Sendable { case left, right, bottom }
  private static let preferredRadius: CGFloat = 19
  private static let tailHalfWidth: CGFloat = 8

  public static func path(in rect: CGRect, tail: Tail, offset: CGFloat, depth: CGFloat) -> CGPath {
    let left = rect.minX + (tail == .left ? depth : 0)
    let right = rect.maxX - (tail == .right ? depth : 0)
    let bottom = rect.minY + (tail == .bottom ? depth : 0)
    let top = rect.maxY
    let radius = min(preferredRadius, (right - left) / 2, (top - bottom) / 2)
    let half = min(tailHalfWidth, max(0, (top - bottom - radius * 2) / 2))
    let tipY = min(max(rect.minY + offset, bottom + radius + half), top - radius - half)
    let tipX = min(
      max(rect.minX + offset, left + radius + tailHalfWidth), right - radius - tailHalfWidth)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left + radius, y: bottom))
    if tail == .bottom {
      path.addLine(to: CGPoint(x: tipX - tailHalfWidth, y: bottom))
      path.addQuadCurve(
        to: CGPoint(x: tipX - 2, y: rect.minY), control: CGPoint(x: tipX - 3, y: bottom))
      path.addQuadCurve(
        to: CGPoint(x: tipX + tailHalfWidth, y: bottom),
        control: CGPoint(x: tipX + 6, y: rect.minY + 2))
    }
    path.addLine(to: CGPoint(x: right - radius, y: bottom))
    path.addQuadCurve(
      to: CGPoint(x: right, y: bottom + radius), control: CGPoint(x: right, y: bottom))
    if tail == .right {
      path.addLine(to: CGPoint(x: right, y: tipY - half))
      path.addQuadCurve(
        to: CGPoint(x: rect.maxX, y: tipY + 2), control: CGPoint(x: right + 2, y: tipY))
      path.addQuadCurve(
        to: CGPoint(x: right, y: tipY + half), control: CGPoint(x: rect.maxX - 2, y: tipY + half))
    }
    path.addLine(to: CGPoint(x: right, y: top - radius))
    path.addQuadCurve(to: CGPoint(x: right - radius, y: top), control: CGPoint(x: right, y: top))
    path.addLine(to: CGPoint(x: left + radius, y: top))
    path.addQuadCurve(to: CGPoint(x: left, y: top - radius), control: CGPoint(x: left, y: top))
    if tail == .left {
      path.addLine(to: CGPoint(x: left, y: tipY + half))
      path.addQuadCurve(
        to: CGPoint(x: rect.minX, y: tipY + 2), control: CGPoint(x: rect.minX + 2, y: tipY + half))
      path.addQuadCurve(
        to: CGPoint(x: left, y: tipY - half), control: CGPoint(x: left - 2, y: tipY))
    }
    path.addLine(to: CGPoint(x: left, y: bottom + radius))
    path.addQuadCurve(
      to: CGPoint(x: left + radius, y: bottom), control: CGPoint(x: left, y: bottom))
    path.closeSubpath()
    return path
  }
}
