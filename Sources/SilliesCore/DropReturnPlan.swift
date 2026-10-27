import CoreGraphics
import Foundation

/// A cancelled drag returns to its pickup anchor, never the release point's projected slot.
public struct DropReturnPlan: Sendable {
  public enum Style: Sendable { case fall, relocate }

  public enum Intent: Sendable { case returnToPerch, activateSkill }

  private static let minimumReturnDuration: TimeInterval = 0.10
  private static let maximumReturnDuration: TimeInterval = 0.30
  private static let fallAcceleration: Double = 9_000
  private static let perchEnvelopeHeightFactor: Double = 1.25

  public let style: Style
  public let destination: CGPoint
  public let duration: TimeInterval

  public init(
    releasedAt release: CGPoint, pickedUpAt origin: CGPoint, destination: CGPoint,
    intent: Intent
  ) {
    self.destination = destination
    style = intent == .activateSkill || release.y < origin.y ? .relocate : .fall
    let distance = hypot(destination.x - release.x, destination.y - release.y)
    duration = min(
      Self.maximumReturnDuration,
      max(Self.minimumReturnDuration, sqrt(2 * distance / Self.fallAcceleration)))
  }

  /// Determines whether dragging a companion at `companionPoint` with cursor `pointer`
  /// over `targetFrame` should show the window drop highlight and radial skill wheel.
  public static func shouldShowDragControls(
    targetFrame: CGRect,
    isSameTargetAsAttached: Bool,
    originWindowFrame: CGRect?,
    pointer: CGPoint,
    companionPoint: CGPoint,
    characterSize: Double
  ) -> Bool {
    guard targetFrame.contains(pointer) else { return false }
    if isSameTargetAsAttached { return true }
    guard let origin = originWindowFrame else { return true }
    return origin.contains(pointer)
      || !origin.insetBy(dx: -characterSize, dy: -characterSize * Self.perchEnvelopeHeightFactor)
        .contains(companionPoint)
  }
}
