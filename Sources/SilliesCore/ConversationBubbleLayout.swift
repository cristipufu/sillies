import Foundation

/// Pure layout: the tail points to the mascot and the body stays inside the visible display.
public struct ConversationBubbleLayout: Equatable, Sendable {
  public enum Tail: Sendable { case top, bottom }
  public static let tailHeight: CGFloat = 12
  private static let displayInset: CGFloat = 8
  private static let cornerClearance: CGFloat = 28
  public let frame: CGRect
  public let tail: Tail
  public let tailOffset: CGFloat
  public init(anchor: CGPoint, size: CGSize, visibleFrame: CGRect) {
    let available = visibleFrame.insetBy(dx: Self.displayInset, dy: Self.displayInset)
    let size = CGSize(
      width: min(size.width, max(0, available.width)),
      height: min(size.height, max(0, available.height)))
    let below = anchor.y - size.height
    tail = below >= available.minY || anchor.y + size.height > available.maxY ? .top : .bottom
    let preferredY = tail == .top ? below : anchor.y
    let x = min(max(anchor.x - size.width / 2, available.minX), available.maxX - size.width)
    let y = min(max(preferredY, available.minY), available.maxY - size.height)
    frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
    let clearance = min(Self.cornerClearance, size.width / 2)
    tailOffset = min(max(anchor.x - x, clearance), size.width - clearance)
  }
}
