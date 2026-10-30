import Foundation

/// Canonical tolerance shared by window verification and transition stability.
public enum WindowFrameComparison {
  public static let tolerance: Double = 6

  public static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    abs(lhs.minX - rhs.minX) <= tolerance
      && abs(lhs.minY - rhs.minY) <= tolerance
      && abs(lhs.width - rhs.width) <= tolerance
      && abs(lhs.height - rhs.height) <= tolerance
  }
}
