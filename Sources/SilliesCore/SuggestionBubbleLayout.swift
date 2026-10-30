import Foundation

/// Places a previously measured bubble without measuring text during window movement.
public struct SuggestionBubbleLayout: Equatable, Sendable {
  public enum Tail: Sendable { case left, right }
  public struct Anchor: Sendable {
    public let companionPoint: CGPoint
    public let characterSize: Double
    public let visibleFrame: CGRect

    public init(companionPoint: CGPoint, characterSize: Double, visibleFrame: CGRect) {
      self.companionPoint = companionPoint
      self.characterSize = characterSize
      self.visibleFrame = visibleFrame
    }
  }
  public static let tailDepth: CGFloat = 12
  public static let shadowInset: CGFloat = 10
  private static let screenInset: CGFloat = 8
  private static let headOffset: CGFloat = 0.45
  private static let characterClearance: CGFloat = 0.42
  private static let tailCornerClearance: CGFloat = 32
  public let frame: CGRect
  public let tail: Tail
  public let tailOffset: CGFloat

  public static func availableSize(in visibleFrame: CGRect) -> CGSize {
    CGSize(
      width: max(0, visibleFrame.width - Self.screenInset * 2),
      height: max(0, visibleFrame.height - Self.screenInset * 2))
  }

  public init(anchor: Anchor, size: CGSize) {
    let visibleFrame = anchor.visibleFrame
    let available = Self.availableSize(in: visibleFrame)
    let size = CGSize(
      width: min(size.width, available.width), height: min(size.height, available.height))
    let head = CGPoint(
      x: anchor.companionPoint.x,
      y: anchor.companionPoint.y + anchor.characterSize * Self.headOffset)
    let clearance = anchor.characterSize * Self.characterClearance
    let rightX = head.x + clearance
    let leftX = head.x - clearance - size.width
    let rightFits = rightX + size.width <= visibleFrame.maxX - Self.screenInset
    tail = rightFits || leftX < visibleFrame.minX + Self.screenInset ? .left : .right
    let preferredX = tail == .left ? rightX : leftX
    let maxX = max(
      visibleFrame.minX + Self.screenInset, visibleFrame.maxX - size.width - Self.screenInset)
    let maxY = max(
      visibleFrame.minY + Self.screenInset, visibleFrame.maxY - size.height - Self.screenInset)
    frame = CGRect(
      x: min(max(preferredX, visibleFrame.minX + Self.screenInset), maxX),
      y: min(
        max(
          head.y - size.height + Self.tailCornerClearance, visibleFrame.minY + Self.screenInset
        ), maxY),
      width: size.width, height: size.height)
    let cornerClearance = min(Self.tailCornerClearance, size.height / 2)
    tailOffset = min(
      max(frame.maxY - head.y, cornerClearance), size.height - cornerClearance)
  }
}
