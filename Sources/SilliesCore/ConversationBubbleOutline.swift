import CoreGraphics
import Foundation

/// Bubble outline in top-left drawing coordinates, shared by every native presentation edge.
public struct ConversationBubbleOutline: Sendable {
  public static let cornerRadius = MascotBubbleContour.cornerRadius
  private static let shoulderControlFraction: CGFloat = 0.25
  private static let tipControlFraction: CGFloat = 0.12
  private let tail: ConversationBubbleLayout.Tail
  private let offset: CGFloat
  private let inset: CGFloat
  private struct Bounds {
    let outer: CGRect
    let body: CGRect
    var radius: CGFloat {
      min(ConversationBubbleOutline.cornerRadius, min(body.width, body.height) / 2)
    }
  }

  public init(tail: ConversationBubbleLayout.Tail, offset: CGFloat, inset: CGFloat = 0) {
    self.tail = tail
    self.offset = offset
    self.inset = inset
  }

  public func path(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    guard !rect.isInfinite, rect.width > inset * 2, rect.height > inset * 2,
      rect.minX.isFinite, rect.minY.isFinite, rect.maxX.isFinite, rect.maxY.isFinite
    else { return path }
    let bounds = bounds(in: rect)
    guard bounds.body.width > 0, bounds.body.height > 0 else { return path }
    path.move(to: CGPoint(x: bounds.body.minX + bounds.radius, y: bounds.body.minY))
    appendTop(to: path, in: bounds)
    appendRight(to: path, in: bounds)
    appendBottom(to: path, in: bounds)
    appendLeft(to: path, in: bounds)
    path.closeSubpath()
    return path
  }

  private func bounds(in rect: CGRect) -> Bounds {
    let outer = rect.insetBy(dx: inset, dy: inset)
    let height = ConversationBubbleLayout.tailHeight
    return .init(
      outer: outer,
      body: CGRect(
        x: outer.minX + (tail == .left ? height : 0), y: outer.minY + (tail == .top ? height : 0),
        width: max(0, outer.width - (tail.isSide ? height : 0)),
        height: max(0, outer.height - (tail.isSide ? 0 : height))))
  }

  private func appendTop(to path: CGMutablePath, in bounds: Bounds) {
    let body = bounds.body
    let height = ConversationBubbleLayout.tailHeight
    if tail == .top {
      appendTail(
        to: path, from: CGPoint(x: offset - height, y: body.minY),
        through: CGPoint(x: offset, y: bounds.outer.minY),
        to: CGPoint(x: offset + height, y: body.minY))
    }
    path.addLine(to: CGPoint(x: body.maxX - bounds.radius, y: body.minY))
    path.addQuadCurve(
      to: CGPoint(x: body.maxX, y: body.minY + bounds.radius),
      control: CGPoint(x: body.maxX, y: body.minY))
  }

  private func appendRight(to path: CGMutablePath, in bounds: Bounds) {
    let body = bounds.body
    let height = ConversationBubbleLayout.tailHeight
    if tail == .right {
      appendTail(
        to: path, from: CGPoint(x: body.maxX, y: offset - height),
        through: CGPoint(x: bounds.outer.maxX, y: offset),
        to: CGPoint(x: body.maxX, y: offset + height))
    }
    path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - bounds.radius))
    path.addQuadCurve(
      to: CGPoint(x: body.maxX - bounds.radius, y: body.maxY),
      control: CGPoint(x: body.maxX, y: body.maxY))
  }

  private func appendBottom(to path: CGMutablePath, in bounds: Bounds) {
    let body = bounds.body
    let height = ConversationBubbleLayout.tailHeight
    if tail == .bottom {
      appendTail(
        to: path, from: CGPoint(x: offset + height, y: body.maxY),
        through: CGPoint(x: offset, y: bounds.outer.maxY),
        to: CGPoint(x: offset - height, y: body.maxY))
    }
    path.addLine(to: CGPoint(x: body.minX + bounds.radius, y: body.maxY))
    path.addQuadCurve(
      to: CGPoint(x: body.minX, y: body.maxY - bounds.radius),
      control: CGPoint(x: body.minX, y: body.maxY))
  }

  private func appendLeft(to path: CGMutablePath, in bounds: Bounds) {
    let body = bounds.body
    let height = ConversationBubbleLayout.tailHeight
    if tail == .left {
      appendTail(
        to: path, from: CGPoint(x: body.minX, y: offset + height),
        through: CGPoint(x: bounds.outer.minX, y: offset),
        to: CGPoint(x: body.minX, y: offset - height))
    }
    path.addLine(to: CGPoint(x: body.minX, y: body.minY + bounds.radius))
    path.addQuadCurve(
      to: CGPoint(x: body.minX + bounds.radius, y: body.minY),
      control: CGPoint(x: body.minX, y: body.minY))
  }

  /// Tangents follow the body at both shoulders and meet smoothly at the tip on every edge.
  private func appendTail(
    to path: CGMutablePath, from start: CGPoint, through tip: CGPoint, to end: CGPoint
  ) {
    let direction = CGVector(dx: end.x - start.x, dy: end.y - start.y)
    func shifted(_ point: CGPoint, by fraction: CGFloat) -> CGPoint {
      CGPoint(x: point.x + direction.dx * fraction, y: point.y + direction.dy * fraction)
    }
    path.addLine(to: start)
    path.addCurve(
      to: tip, control1: shifted(start, by: Self.shoulderControlFraction),
      control2: shifted(tip, by: -Self.tipControlFraction))
    path.addCurve(
      to: end, control1: shifted(tip, by: Self.tipControlFraction),
      control2: shifted(end, by: -Self.shoulderControlFraction))
  }
}
