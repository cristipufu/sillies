import CoreGraphics
import Foundation

/// A long arc carried by a small moving panel; the available desktop bounds the flight.
public enum PlayfulPlaneFlight {
  public static let panelSize = CGSize(width: 80, height: 64)
  private static let travelDistance = 460.0
  private static let launchHeightRatio = 0.7
  private static let arcHeight = 82.0
  private static let releaseProgress = 0.12
  private static let margin = 8.0

  public static func frame(origin: CGPoint, size: Double, visible: CGRect, progress: Double)
    -> CGRect
  {
    let halfWidth = panelSize.width / 2
    let left = visible.minX + halfWidth + margin
    let right = visible.maxX - halfWidth - margin
    let startX = min(max(origin.x, left), right)
    let direction = right - startX >= startX - left ? 1.0 : -1.0
    let distance = min(travelDistance, direction > 0 ? right - startX : startX - left)
    let flight = min(max((progress - releaseProgress) / (1 - releaseProgress), 0), 1)
    let travel = 1 - pow(1 - flight, 1.4)
    let floor = origin.y + size * launchHeightRatio
    let headroom = max(0, visible.maxY - floor - panelSize.height - margin)
    return CGRect(
      x: startX + direction * distance * travel - halfWidth,
      y: floor + min(arcHeight, headroom) * sin(.pi * flight),
      width: panelSize.width, height: panelSize.height)
  }

  public static func facesRight(origin: CGPoint, visible: CGRect) -> Bool {
    visible.maxX - origin.x >= origin.x - visible.minX
  }
}
