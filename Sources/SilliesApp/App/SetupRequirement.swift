import Foundation
import SilliesChat
import SilliesCore

struct SetupRequirement: Identifiable {
  enum ID: String { case replyModel, microphone, recognition, voice, screenRecording }
  enum State { case ready, needsAction }
  enum Action {
    case settings(SettingsDestination)
    case permission(SessionFailure.RecoveryAction)
  }
  let id: ID
  let title: String
  let detail: String
  let state: State
  let action: Action
  var isOptional = false
  var isSatisfied: Bool { state == .ready || isOptional }

  init(_ check: ConversationReadiness.Check) {
    switch check.requirement {
    case .replyModel:
      id = .replyModel
      title = String(localized: "Replies")
      action = .settings(.intelligence)
    case .microphone:
      id = .microphone
      title = String(localized: "Microphone")
      action = .permission(.openMicrophoneSettings)
    case .recognition:
      id = .recognition
      title = String(localized: "Speech recognition")
      action = .settings(.speech)
    case .voice:
      id = .voice
      title = String(localized: "Voice")
      action = .settings(.voices)
    }
    switch check.result {
    case .available:
      state = .ready
      detail = String(localized: "Ready")
    case .permissionRequired(let failure):
      state = .needsAction
      detail = failure.message
    default:
      state = .needsAction
      detail = check.result.notice?.message ?? String(localized: "Check your setup and try again.")
    }
  }

  init(permission: SessionFailure.RecoveryAction, granted: Bool) {
    id = permission == .openMicrophoneSettings ? .microphone : .screenRecording
    title =
      permission == .openMicrophoneSettings
      ? String(localized: "Microphone") : String(localized: "Screen & system audio")
    detail =
      granted ? String(localized: "Ready") : String(localized: "Allow access when you’re ready.")
    state = granted ? .ready : .needsAction
    action = .permission(permission)
  }
}
