import CoreGraphics
import Foundation

/// A cancelled drag returns to its pickup anchor, never the release point's projected slot.
public struct DropReturnPlan: Sendable {
  public enum Style: Sendable { case fall, relocate }

  public let style: Style
  public let destination: CGPoint
  public let duration: TimeInterval

  public init(
    releasedAt release: CGPoint, pickedUpAt origin: CGPoint, destination: CGPoint,
    selectedSkill: Bool
  ) {
    self.destination = destination
    style = selectedSkill || release.y < origin.y ? .relocate : .fall
    let distance = hypot(destination.x - release.x, destination.y - release.y)
    duration = min(0.30, max(0.10, sqrt(2 * distance / 9_000)))
  }
}
