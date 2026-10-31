package enum ChatNotice {
  package enum SettingsDestination { case textModels, voices }
  case textUnavailable(String)
  case voiceUnavailable(String)
  case reviewMessage(String)

  package var message: String {
    switch self {
    case .textUnavailable(let message), .voiceUnavailable(let message), .reviewMessage(let message):
      message
    }
  }

  package var settingsDestination: SettingsDestination? {
    switch self {
    case .textUnavailable: .textModels
    case .voiceUnavailable: .voices
    case .reviewMessage: nil
    }
  }
}
