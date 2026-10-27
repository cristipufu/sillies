import Foundation

/// Fixed-size speech geometry avoids text measurement while a bound window is moving.
public struct SuggestionBubbleLayout: Equatable, Sendable {
  public enum Tail: Sendable { case left, right }
  public static let size = CGSize(width: 324, height: 212)
  public static let tailDepth: CGFloat = 12
  public static let shadowInset: CGFloat = 10
  private static let screenInset: CGFloat = 8
  private static let headOffset: CGFloat = 0.45
  private static let characterClearance: CGFloat = 0.42
  private static let tailCornerClearance: CGFloat = 32
  public let frame: CGRect
  public let tail: Tail
  public let tailOffset: CGFloat

  public init(companionPoint: CGPoint, characterSize: Double, visibleFrame: CGRect) {
    let head = CGPoint(x: companionPoint.x, y: companionPoint.y + characterSize * Self.headOffset)
    let clearance = characterSize * Self.characterClearance
    let rightX = head.x + clearance
    let leftX = head.x - clearance - Self.size.width
    let rightFits = rightX + Self.size.width <= visibleFrame.maxX - Self.screenInset
    tail = rightFits || leftX < visibleFrame.minX + Self.screenInset ? .left : .right
    let preferredX = tail == .left ? rightX : leftX
    let maxX = max(
      visibleFrame.minX + Self.screenInset, visibleFrame.maxX - Self.size.width - Self.screenInset)
    let maxY = max(
      visibleFrame.minY + Self.screenInset, visibleFrame.maxY - Self.size.height - Self.screenInset)
    frame = CGRect(
      x: min(max(preferredX, visibleFrame.minX + Self.screenInset), maxX),
      y: min(
        max(
          head.y - Self.size.height + Self.tailCornerClearance, visibleFrame.minY + Self.screenInset
        ), maxY),
      width: Self.size.width, height: Self.size.height)
    tailOffset = min(
      max(frame.maxY - head.y, Self.tailCornerClearance),
      Self.size.height - Self.tailCornerClearance)
  }
}
