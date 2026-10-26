import CoreGraphics

/// Native bounds stay outside the attached window, independently of decorative layer masks.
public struct CompanionWindowLayout: Sendable {
  public static let runtimeCanvasDimension: Double = 256
  private static let halfRuntimeCanvas: Double = runtimeCanvasDimension / 2
  private static let percentScale: Double = 100
  private static let minimumCroppedDimension: Double = 1

  public let frame: CGRect
  public let contactOffset: CGPoint

  public init(contact: CGPoint, size: Double, window: CGRect?, edge: PerchSurface.Edge) {
    let half = Self.halfRuntimeCanvas * size / Self.percentScale
    let halfDesignWidth = AttachmentPose.designCanvasSize * 0.5 * size / Self.percentScale
    let canvas = CGRect(x: contact.x - half, y: contact.y - half, width: half * 2, height: half * 2)
    var native = canvas
    if let window {
      switch edge {
      case .top:
        let bottom = max(canvas.minY, window.maxY)
        native = CGRect(
          x: contact.x - halfDesignWidth, y: bottom, width: halfDesignWidth * 2,
          height: max(Self.minimumCroppedDimension, canvas.maxY - bottom))
      case .left:
        let right = min(canvas.maxX, window.minX)
        native = CGRect(
          x: min(canvas.minX, right - Self.minimumCroppedDimension), y: canvas.minY,
          width: max(Self.minimumCroppedDimension, right - canvas.minX), height: canvas.height)
      case .right:
        let left = max(canvas.minX, window.maxX)
        native = CGRect(
          x: left, y: canvas.minY,
          width: max(Self.minimumCroppedDimension, canvas.maxX - left), height: canvas.height)
      default: break
      }
    } else if edge == .desktop {
      native = CGRect(
        x: contact.x - halfDesignWidth, y: canvas.minY, width: halfDesignWidth * 2,
        height: canvas.height)
    }
    frame = native
    contactOffset = CGPoint(x: contact.x - native.minX, y: contact.y - native.minY)
  }
}
