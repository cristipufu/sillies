import SilliesCore

enum SpeechLanguageGuidance {
  static func title(for control: SpeechModelDescriptor.Capabilities.LanguageControl) -> String {
    control == .hinted ? String(localized: "Language hint") : String(localized: "Spoken language")
  }

  static func detail(for control: SpeechModelDescriptor.Capabilities.LanguageControl) -> String {
    switch control {
    case .automatic: String(localized: "Detects the spoken language automatically.")
    case .hinted:
      String(
        localized:
          "A hint guides the writing script, but cannot force a language. Choose automatic for speech that mixes languages or scripts."
      )
    case .selectable:
      String(
        localized:
          "Language changes apply to new speech. Model changes in Settings apply to the next session."
      )
    }
  }
}
