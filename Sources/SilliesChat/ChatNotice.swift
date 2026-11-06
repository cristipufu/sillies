import Foundation

package enum ChatNotice: Sendable {
  package enum SettingsDestination: Sendable {
    case textModels, voices, recognition
    package var title: String {
      switch self {
      case .textModels: String(localized: "Choose a text model…")
      case .voices: String(localized: "Choose a voice…")
      case .recognition: String(localized: "Choose a speech model…")
      }
    }
  }
  case textUnavailable(String)
  case voiceUnavailable(String)
  case recognitionUnavailable(String)
  case reviewMessage(String)

  package var message: String {
    switch self {
    case .textUnavailable(let message), .voiceUnavailable(let message),
      .recognitionUnavailable(let message), .reviewMessage(let message):
      message
    }
  }

  package var settingsDestination: SettingsDestination? {
    switch self {
    case .textUnavailable: .textModels
    case .voiceUnavailable: .voices
    case .recognitionUnavailable: .recognition
    case .reviewMessage: nil
    }
  }
}
