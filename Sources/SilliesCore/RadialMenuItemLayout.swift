import Foundation

/// Visible icon and label regions; gaps and shadows must pass input through.
public struct RadialMenuItemLayout: Sendable {
  public static let iconDiameter: CGFloat = 48
  public static let titleHeight: CGFloat = 20
  public static let spacing: CGFloat = 5
  public static let selectedScale: CGFloat = 1.12
  public static let height = iconDiameter + spacing + titleHeight
  public let center: CGPoint
  public let titleWidth: CGFloat
  public init(center: CGPoint, titleWidth: CGFloat) {
    self.center = center
    self.titleWidth = titleWidth
  }
  public func contains(_ point: CGPoint) -> Bool {
    let x = abs(point.x - center.x)
    let y = point.y - center.y
    let iconY = (Self.height - Self.iconDiameter) / 2
    if hypot(x, y - iconY) <= Self.iconDiameter / 2 { return true }
    let labelY = -(Self.height - Self.titleHeight) / 2
    let radius = Self.titleHeight / 2
    let segment = max(0, titleWidth / 2 - radius)
    return hypot(max(0, x - segment), y - labelY) <= radius
  }
}
