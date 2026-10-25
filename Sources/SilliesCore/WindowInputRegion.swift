import CoreGraphics

/// Preserve window manipulation while letting deliberate Play mode target pets over background content.
public enum WindowInputRegion {
  public static let resizeBorderWidth: Double = 10
  public static let protectedHeaderHeight: Double = 64

  public static func protectsControls(at point: CGPoint, frame: CGRect) -> Bool {
    let border = resizeBorderWidth
    guard frame.insetBy(dx: -border, dy: -border).contains(point) else { return false }
    let insideBorders = frame.insetBy(dx: border, dy: border).contains(point)
    let inHeader = point.y >= frame.maxY - min(protectedHeaderHeight, frame.height)
    return !insideBorders || inHeader
  }
}
