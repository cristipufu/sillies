import Foundation
import SilliesCore

@MainActor
final class CompanionHUDModel {
  struct Controls {
    let openSession: () -> Void
    let undoStash: (UUID) -> Void
    let stopSkill: () -> Void
    let unbind: () -> Void
    let openVault: (UUID) -> Void
    let focusWindow: (WindowTargetCandidate) -> Void
  }

  func configure(_ controls: Controls) {
    onOpenSession = controls.openSession
    onUndoStash = controls.undoStash
    onStopSkill = controls.stopSkill
    onUnbind = controls.unbind
    onOpenVault = controls.openVault
    onFocusWindow = controls.focusWindow
  }

  func updatePresentation(_ presentation: SkillPresentation) {
    persistenceError = presentation.persistenceError
    completedRecord = presentation.completedRecord
    audioSession = presentation.audioSession
  }
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
