import Foundation
import SilliesCore

@MainActor
final class CompanionHUDModel {
  var state: CompanionBindingState = .followingFocusedWindow
  var persistenceError: String?
  var completedRecord: SessionRecord?
  var audioSession: AudioSessionPresentation?
  var onOpenSession: (() -> Void)?
  var onUndoStash: ((UUID) -> Void)?
  var onStopSkill: (() -> Void)?
  var onUnbind: (() -> Void)?
  var onOpenVault: ((UUID) -> Void)?
  var onFocusWindow: ((WindowTargetCandidate) -> Void)?
}
