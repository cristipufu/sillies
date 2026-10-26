import CoreGraphics
import Foundation

/// Rigid pointer-to-window mapping. Metadata validates a gesture; it does not drive its frames.
public struct PointerWindowGesture: Sendable {
  public static let hitSlop: Double = 12
  public static let resizeEdgeTolerance: Double = 9
  public static let topResizeEdgeTolerance: Double = 7
  public static let draggableHeaderDepth: Double = 84
  public static let defaultMinimumWindowSize = CGSize(width: 120, height: 70)
  public static let defaultMatchTolerance: Double = 12

  public struct Edges: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let left = Self(rawValue: 1)
    public static let right = Self(rawValue: 2)
    public static let top = Self(rawValue: 4)
    public static let bottom = Self(rawValue: 8)
  }
  public enum Kind: Sendable, Equatable {
    case move
    case resize(Edges)
  }
  public let kind: Kind
  public let initialFrame: CGRect
  public let initialPointer: CGPoint
  public let startedAt: TimeInterval
  public let centered: Bool
  public let proportional: Bool

  public init(
    kind: Kind, frame: CGRect, pointer: CGPoint, at time: TimeInterval,
    centered: Bool = false, proportional: Bool = false
  ) {
    self.kind = kind
    initialFrame = frame
    initialPointer = pointer
    startedAt = time
    self.centered = centered
    self.proportional = proportional
  }

  public init?(
    frame: CGRect, pointer: CGPoint, at time: TimeInterval, centered: Bool = false,
    proportional: Bool = false
  ) {
    guard frame.insetBy(dx: -Self.hitSlop, dy: -Self.hitSlop).contains(pointer) else { return nil }
    var edges: Edges = []
    if abs(pointer.x - frame.minX) <= Self.resizeEdgeTolerance {
      edges.insert(.left)
    } else if abs(pointer.x - frame.maxX) <= Self.resizeEdgeTolerance {
      edges.insert(.right)
    }
    if abs(pointer.y - frame.maxY) <= Self.topResizeEdgeTolerance {
      edges.insert(.top)
    } else if abs(pointer.y - frame.minY) <= Self.resizeEdgeTolerance {
      edges.insert(.bottom)
    }
    if !edges.isEmpty {
      kind = .resize(edges)
    } else if pointer.y >= frame.maxY - Self.draggableHeaderDepth
      && pointer.y < frame.maxY - Self.topResizeEdgeTolerance
    {
      kind = .move
    } else {
      return nil
    }
    initialFrame = frame
    initialPointer = pointer
    startedAt = time
    self.centered = centered
    self.proportional = proportional
  }

  public func frame(
    at pointer: CGPoint, minimumSize: CGSize = Self.defaultMinimumWindowSize
  ) -> CGRect {
    let dx = pointer.x - initialPointer.x
    let dy = pointer.y - initialPointer.y
    switch kind {
    case .move: return initialFrame.offsetBy(dx: dx, dy: dy)
    case .resize(let edges):
      var left = initialFrame.minX
      var right = initialFrame.maxX
      var bottom = initialFrame.minY
      var top = initialFrame.maxY
      if edges.contains(.left) {
        left += dx
        if centered { right -= dx }
      }
      if edges.contains(.right) {
        right += dx
        if centered { left -= dx }
      }
      if edges.contains(.bottom) {
        bottom += dy
        if centered { top -= dy }
      }
      if edges.contains(.top) {
        top += dy
        if centered { bottom -= dy }
      }
      var width = max(minimumSize.width, right - left)
      var height = max(minimumSize.height, top - bottom)
      if proportional {
        let aspect = initialFrame.width / initialFrame.height
        if edges.contains(.left) || edges.contains(.right) {
          height = max(minimumSize.height, width / aspect)
        } else {
          width = max(minimumSize.width, height * aspect)
        }
      }
      if centered {
        left = initialFrame.midX - width / 2
        bottom = initialFrame.midY - height / 2
      } else {
        if edges.contains(.left) { left = initialFrame.maxX - width }
        if edges.contains(.bottom) { bottom = initialFrame.maxY - height }
      }
      return CGRect(x: left, y: bottom, width: width, height: height)
    }
  }

  /// A delayed snapshot may match any recent input, not just the newest cursor position.
  public func matches(
    _ authoritative: CGRect, recentPointers: [CGPoint],
    tolerance: Double = Self.defaultMatchTolerance
  ) -> Bool {
    recentPointers.contains { point in
      let candidate = frame(at: point)
      return abs(candidate.minX - authoritative.minX) <= tolerance
        && abs(candidate.minY - authoritative.minY) <= tolerance
        && abs(candidate.width - authoritative.width) <= tolerance
        && abs(candidate.height - authoritative.height) <= tolerance
    }
  }
}
