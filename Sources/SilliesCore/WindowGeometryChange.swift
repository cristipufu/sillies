import Foundation

public struct WindowGeometryChange: Sendable {
  private static let minimumFrameElapsed: Double = 0.016

  public let previous: CGRect
  public let current: CGRect
  public let elapsed: Double
  public let resized: Bool
  public init(previous: CGRect, current: CGRect, elapsed: Double, resized: Bool) {
    self.previous = previous
    self.current = current
    self.elapsed = elapsed
    self.resized = resized
  }

  public var horizontalSpeed: Double {
    (current.midX - previous.midX) / max(elapsed, Self.minimumFrameElapsed)
  }
  public var verticalSpeed: Double {
    (current.maxY - previous.maxY) / max(elapsed, Self.minimumFrameElapsed)
  }
  public var widthSpeed: Double {
    (current.width - previous.width) / max(elapsed, Self.minimumFrameElapsed)
  }
}
