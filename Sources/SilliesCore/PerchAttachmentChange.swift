import Foundation

/// Preserves a companion's normalized slot while its window moves, resizes, or changes edges.
public struct PerchAttachmentChange: Sendable {
  public enum Transition: Sendable { case unchanged, moved, reattached }
  public struct Previous: Sendable {
    public let surface: PerchSurface?
    public let windowID: UInt32?
    public let position: CGPoint
    public let heldFraction: Double?

    public init(surface: PerchSurface?, windowID: UInt32?, position: CGPoint, heldFraction: Double?)
    {
      self.surface = surface
      self.windowID = windowID
      self.position = position
      self.heldFraction = heldFraction
    }
  }

  private static let spanChangeTolerance: Double = 0.5
  public let surface: PerchSurface
  public let target: CGPoint
  public let transition: Transition
  public let needsArrangement: Bool

  public init(
    previous: Previous, surface: PerchSurface, windowID: UInt32?, fallbackFraction: Double
  ) {
    self.surface = surface
    let fraction =
      previous.heldFraction
      ?? previous.surface?.fraction(for: previous.position, fallback: fallbackFraction)
      ?? fallbackFraction
    target = surface.point(at: fraction)
    if previous.windowID != windowID || previous.surface?.edge != surface.edge {
      transition = .reattached
    } else {
      transition = previous.surface == surface ? .unchanged : .moved
    }
    needsArrangement =
      transition == .reattached
      || abs((previous.surface?.spanLength ?? 0) - surface.spanLength) > Self.spanChangeTolerance
      || abs((previous.surface?.presentationSize ?? 0) - surface.presentationSize)
        > Self.spanChangeTolerance
  }
}
