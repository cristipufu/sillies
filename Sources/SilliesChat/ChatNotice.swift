package enum ChatNotice {
  case voiceUnavailable(String)
  case reviewMessage(String)

  package var message: String {
    switch self {
    case .voiceUnavailable(let message), .reviewMessage(let message): message
    }
  }

  package var offersVoiceSettings: Bool {
    if case .voiceUnavailable = self { true } else { false }
  }
}
