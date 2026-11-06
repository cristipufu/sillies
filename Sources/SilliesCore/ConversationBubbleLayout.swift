import Foundation

/// Pure layout: the tail points to the mascot and the body stays inside the visible display.
public struct ConversationBubbleLayout: Equatable, Sendable {
  public enum Tail: Sendable {
    case top, bottom, left, right
    public var isSide: Bool { self == .left || self == .right }
  }
  public static let tailHeight: CGFloat = 12
  private static let displayInset: CGFloat = 8
  private static let cornerClearance = ConversationBubbleOutline.cornerRadius + tailHeight
  public let frame: CGRect
  public let tail: Tail
  public let tailOffset: CGFloat

  public init(anchor: CGPoint, size: CGSize, visibleFrame: CGRect, edge: PerchSurface.Edge = .top) {
    let available = visibleFrame.insetBy(dx: Self.displayInset, dy: Self.displayInset)
    let size = CGSize(
      width: min(size.width, max(0, available.width)),
      height: min(size.height, max(0, available.height)))
    tail = Self.preferredTail(anchor: anchor, size: size, available: available, edge: edge)
    let preferred = Self.origin(anchor: anchor, size: size, tail: tail)
    let x = min(max(preferred.x, available.minX), available.maxX - size.width)
    let y = min(max(preferred.y, available.minY), available.maxY - size.height)
    frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
    let span = tail.isSide ? size.height : size.width
    let offset = tail.isSide ? frame.maxY - anchor.y : anchor.x - x
    let clearance = min(Self.cornerClearance, span / 2)
    tailOffset = min(max(offset, clearance), span - clearance)
  }

  /// Preserve the content's dimensions when the tail switches between a vertical and side edge.
  public static func windowSize(forBody body: CGSize, edge: PerchSurface.Edge) -> CGSize {
    let side = edge == .left || edge == .right
    return CGSize(
      width: body.width + (side ? tailHeight : 0),
      height: body.height + (side ? 0 : tailHeight))
  }

  private static func preferredTail(
    anchor: CGPoint, size: CGSize, available: CGRect,
    edge: PerchSurface.Edge
  ) -> Tail {
    switch edge {
    case .left:
      return anchor.x + size.width <= available.maxX || anchor.x - size.width < available.minX
        ? .left : .right
    case .right:
      return anchor.x - size.width >= available.minX || anchor.x + size.width > available.maxX
        ? .right : .left
    default:
      return anchor.y - size.height >= available.minY || anchor.y + size.height > available.maxY
        ? .top : .bottom
    }
  }

  private static func origin(anchor: CGPoint, size: CGSize, tail: Tail) -> CGPoint {
    switch tail {
    case .top: CGPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height)
    case .bottom: CGPoint(x: anchor.x - size.width / 2, y: anchor.y)
    case .left: CGPoint(x: anchor.x, y: anchor.y - size.height / 2)
    case .right: CGPoint(x: anchor.x - size.width, y: anchor.y - size.height / 2)
    }
  }
}
