import Foundation
import SilliesChat
import SilliesCore

@MainActor
final class CompanionHUDModel {
  enum Surface { case card, speechBubble }

  func surface(for state: CompanionBindingState) -> Surface {
    switch state {
    case .active(_, let skill, _, _, _), .completed(_, let skill, _, _, _):
      return skill.isAudioSession || (skill == .chat && conversation?.mode == .talk)
        ? .speechBubble : .card
    case .followingFocusedWindow:
      return .card
    }
  }

  struct Controls {
    let openSession: () -> Void
    let undoStash: (UUID) -> Void
    let stopSkill: () -> Void
    let unbind: () -> Void
    let openVault: (UUID) -> Void
    let focusWindow: (WindowTargetCandidate) -> Void
    let openChatSettings: (ChatNotice.SettingsDestination) -> Void
  }

  func configure(_ controls: Controls) {
    onOpenSession = controls.openSession
    onUndoStash = controls.undoStash
    onStopSkill = controls.stopSkill
    onUnbind = controls.unbind
    onOpenVault = controls.openVault
    onFocusWindow = controls.focusWindow
    onOpenChatSettings = controls.openChatSettings
  }

  func updatePresentation(_ presentation: SkillPresentation) {
    persistenceError = presentation.persistenceError
    completedRecord = presentation.completedRecord
    audioSession = presentation.audioSession
    conversation = presentation.conversation
  }
  func showsHUD(for state: CompanionBindingState) -> Bool {
    if case .active(_, .chat, _, _, _) = state { return conversation?.mode == .talk }
    return state.showsTaskHUD
  }
  var state: CompanionBindingState = .followingFocusedWindow
  var persistenceError: String?
  var completedRecord: SessionRecordHeader?
  var audioSession: AudioSessionPresentation?
  var conversation: ChatSession?
  var onOpenSession: (() -> Void)?
  var onUndoStash: ((UUID) -> Void)?
  var onStopSkill: (() -> Void)?
  var onUnbind: (() -> Void)?
  var onOpenVault: ((UUID) -> Void)?
  var onFocusWindow: ((WindowTargetCandidate) -> Void)?
  var onOpenChatSettings: ((ChatNotice.SettingsDestination) -> Void)?
}
