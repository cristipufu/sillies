import CoreGraphics
import Foundation

/// A cancelled drag returns to its pickup anchor, never the release point's projected slot.
public struct DropReturnPlan: Sendable {
  public enum Style: Sendable { case fall, relocate }

  public static let windowDropInteriorInset: Double = 14

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
      || !origin.insetBy(dx: -characterSize, dy: -characterSize * 1.25).contains(companionPoint)
  }

  /// Determines whether releasing a companion at `companionPoint` with cursor `pointer`
  /// inside `targetFrame` should bind the companion to that target window.
  public static func shouldBindOnDrop(
    targetFrame: CGRect,
    currentAttachedWindowFrame: CGRect?,
    pointer: CGPoint,
    companionPoint: CGPoint,
    characterSize: Double
  ) -> Bool {
    let interior = targetFrame.insetBy(
      dx: windowDropInteriorInset, dy: windowDropInteriorInset)
    guard interior.contains(pointer) else { return false }
    if let currentWindow = currentAttachedWindowFrame {
      let currentInterior = currentWindow.insetBy(
        dx: windowDropInteriorInset, dy: windowDropInteriorInset)
      if currentInterior.contains(pointer) {
        return true
      }
      let currentPerchEnvelope = currentWindow.insetBy(
        dx: -characterSize, dy: -characterSize * 1.25)
      if currentPerchEnvelope.contains(companionPoint) {
        return false
      }
    }
    return true
  }
}
