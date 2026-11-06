import Foundation

/// Places a previously measured bubble without measuring text during window movement.
public struct CompanionSpeechBubbleLayout: Equatable, Sendable {
  public enum Tail: Sendable { case left, right }
  public enum Placement: Sendable { case besideHead, aboveContact }
  public struct Anchor: Sendable {
    public let companionPoint: CGPoint
    public let characterSize: Double
    public let visibleFrame: CGRect
    public let windowFrame: CGRect?

    public init(
      companionPoint: CGPoint, characterSize: Double, visibleFrame: CGRect,
      windowFrame: CGRect? = nil
    ) {
      self.companionPoint = companionPoint
      self.characterSize = characterSize
      self.visibleFrame = visibleFrame
      self.windowFrame = windowFrame
    }
  }
  public static let tailDepth: CGFloat = 12
  public static let shadowInset: CGFloat = 10
  public static let contactClearance: CGFloat = 16
  private static let screenInset: CGFloat = 8
  private static let headOffset: CGFloat = 0.45
  private static let characterClearance: CGFloat = 0.42
  private static let tailCornerClearance: CGFloat = 32
  private static let bubbleSeparation: CGFloat = 8
  public let frame: CGRect
  public let tail: Tail
  public let tailOffset: CGFloat

  public static func availableSize(in visibleFrame: CGRect) -> CGSize {
    CGSize(
      width: max(0, visibleFrame.width - Self.screenInset * 2),
      height: max(0, visibleFrame.height - Self.screenInset * 2))
  }

  public init(anchor: Anchor, size: CGSize, placement: Placement = .besideHead) {
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
    let horizontal = Self.horizontalBounds(anchor: anchor, width: size.width, placement: placement)
    let rightFits = rightX + size.width <= horizontal.upperBound
    let leftFits = leftX >= horizontal.lowerBound
    if rightFits {
      tail = .left
    } else if leftFits {
      tail = .right
    } else {
      tail = head.x <= (horizontal.lowerBound + horizontal.upperBound) / 2 ? .left : .right
    }
    let preferredX = tail == .left ? rightX : leftX
    let maxX = max(horizontal.lowerBound, horizontal.upperBound - size.width)
    let maxY = max(
      visibleFrame.minY + Self.screenInset, visibleFrame.maxY - size.height - Self.screenInset)
    let headAlignedY = head.y - size.height + Self.tailCornerClearance
    let preferredY: CGFloat
    switch placement {
    case .besideHead: preferredY = headAlignedY
    case .aboveContact:
      preferredY = max(headAlignedY, anchor.companionPoint.y + Self.contactClearance)
    }
    frame = CGRect(
      x: min(max(preferredX, horizontal.lowerBound), maxX),
      y: min(max(preferredY, visibleFrame.minY + Self.screenInset), maxY),
      width: size.width, height: size.height)
    tailOffset = Self.tailOffset(frame: frame, headY: head.y)
  }

  /// A thought yields to recording controls when both cannot fit on the screen.
  public init?(anchor: Anchor, size: CGSize, avoiding occupiedFrame: CGRect) {
    let preferred = Self(anchor: anchor, size: size)
    let exclusion = occupiedFrame.insetBy(dx: -Self.bubbleSeparation, dy: -Self.bubbleSeparation)
    if !preferred.frame.intersects(exclusion) {
      self = preferred
      return
    }
    let oppositeTail: Tail = preferred.tail == .left ? .right : .left
    let clearance = anchor.characterSize * Self.characterClearance
    let oppositeX =
      oppositeTail == .left
      ? anchor.companionPoint.x + clearance
      : anchor.companionPoint.x - clearance - preferred.frame.width
    let candidates: [(CGPoint, Tail)] = [
      (CGPoint(x: oppositeX, y: preferred.frame.minY), oppositeTail),
      (CGPoint(x: preferred.frame.minX, y: exclusion.maxY), preferred.tail),
      (
        CGPoint(x: preferred.frame.minX, y: exclusion.minY - preferred.frame.height), preferred.tail
      ),
    ]
    let available = anchor.visibleFrame.insetBy(dx: Self.screenInset, dy: Self.screenInset)
    for (origin, tail) in candidates {
      let frame = CGRect(origin: origin, size: preferred.frame.size)
      guard available.contains(frame), !frame.intersects(exclusion) else { continue }
      self.init(frame: frame, tail: tail, anchor: anchor)
      return
    }
    return nil
  }

  private init(frame: CGRect, tail: Tail, anchor: Anchor) {
    self.frame = frame
    self.tail = tail
    tailOffset = Self.tailOffset(
      frame: frame, headY: anchor.companionPoint.y + anchor.characterSize * Self.headOffset)
  }

  private static func tailOffset(frame: CGRect, headY: CGFloat) -> CGFloat {
    let clearance = min(Self.tailCornerClearance, frame.height / 2)
    return min(max(frame.maxY - headY, clearance), frame.height - clearance)
  }

  private static func horizontalBounds(anchor: Anchor, width: CGFloat, placement: Placement)
    -> ClosedRange<CGFloat>
  {
    let minimum = anchor.visibleFrame.minX + screenInset
    let maximum = max(minimum, anchor.visibleFrame.maxX - screenInset)
    guard placement == .aboveContact, let window = anchor.windowFrame,
      window.minX.isFinite, window.maxX.isFinite
    else { return minimum...maximum }
    let left = max(minimum, window.minX)
    let right = min(maximum, window.maxX)
    guard right - left >= width else { return minimum...maximum }
    return left...right
  }
}
