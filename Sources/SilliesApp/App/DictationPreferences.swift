import Foundation
import Observation
import SilliesCore

@MainActor @Observable
final class DictationPreferences {
  private let defaults: UserDefaults
  var style: DictationOutputStyle {
    didSet { defaults.set(style.rawValue, forKey: "dictation.outputStyle") }
  }
  var languageIdentifier: String {
    didSet { defaults.set(languageIdentifier, forKey: "dictation.language") }
  }
  var translationLanguage: String {
    didSet { defaults.set(translationLanguage, forKey: "writing.translationLanguage") }
  }
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    style =
      DictationOutputStyle(rawValue: defaults.string(forKey: "dictation.outputStyle") ?? "")
      ?? .lightlyCleaned
    languageIdentifier = defaults.string(forKey: "dictation.language") ?? "auto"
    translationLanguage = defaults.string(forKey: "writing.translationLanguage") ?? "en"
  }
}
