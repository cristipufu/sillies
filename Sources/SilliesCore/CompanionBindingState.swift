import CoreGraphics
import Foundation

/// Lifecycle state of a companion's attachment to a specific window task.
public enum CompanionBindingState: Equatable, Sendable {
  case followingFocusedWindow
  case active(
    target: WindowTargetCandidate?, skill: CompanionSkillKind, startedAt: TimeInterval,
    statusDetail: String = "", audioLevel: Double = 0)
  case completed(
    target: WindowTargetCandidate?, skill: CompanionSkillKind, summary: String,
    recordID: UUID, expiresAt: TimeInterval)

  public var boundTarget: WindowTargetCandidate? {
    switch self {
    case .followingFocusedWindow: nil
    case .active(let target, _, _, _, _),
      .completed(let target, _, _, _, _):
      target
    }
  }

  public var hasPresentation: Bool { self != .followingFocusedWindow }

  public var isBound: Bool { boundTarget != nil }
}
