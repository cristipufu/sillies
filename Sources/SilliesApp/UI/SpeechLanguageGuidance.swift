import SilliesCore

enum SpeechLanguageGuidance {
  static func title(for control: SpeechModelDescriptor.Capabilities.LanguageControl) -> String {
    control == .hinted ? "Language hint" : "Spoken language"
  }

  static func detail(for control: SpeechModelDescriptor.Capabilities.LanguageControl) -> String {
    switch control {
    case .automatic: "Detects the spoken language automatically."
    case .hinted:
      "A hint guides the writing script, but cannot force a language. English and Romanian can still mix. Choose automatic for mixed scripts."
    case .selectable:
      "Language changes apply to new speech. Model changes in Settings apply to the next session."
    }
  }
}
