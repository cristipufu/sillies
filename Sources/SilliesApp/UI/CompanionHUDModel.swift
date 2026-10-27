import Foundation
import SilliesCore

@MainActor
final class CompanionHUDModel {
  var state: CompanionBindingState = .followingFocusedWindow
  var onStopSkill: (() -> Void)?
  var onUnbind: (() -> Void)?
  var onOpenVault: ((UUID) -> Void)?
  var onFocusWindow: ((WindowTargetCandidate) -> Void)?
}
