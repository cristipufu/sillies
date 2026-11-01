import Foundation

/// Wait for release so a window move, resize or selection drag never becomes a dismissal.
public struct OutsideClickDismissal: Sendable {
  private struct Press: Sendable {
    let point: CGPoint
    let button: Int
  }
  private static let clickTolerance: CGFloat = 4
  private var press: Press?
  public init() {}

  public mutating func begin(at point: CGPoint, button: Int) {
    press = Press(point: point, button: button)
  }

  public mutating func cancel() { press = nil }

  public mutating func release(at point: CGPoint, button: Int) -> Bool {
    guard let press, press.button == button else { return false }
    self.press = nil
    return hypot(point.x - press.point.x, point.y - press.point.y) <= Self.clickTolerance
  }
}
