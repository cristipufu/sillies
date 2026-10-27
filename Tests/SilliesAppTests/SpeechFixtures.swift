import Foundation

@testable import SilliesApp

let fixtureEnglish = SpeechLanguage(
  id: "en-US", name: "English (United States)",
  isInstalled: true, supportsNotes: true)
let fixtureFrench = SpeechLanguage(
  id: "fr-FR", name: "French (France)",
  isInstalled: true, supportsNotes: true)

@MainActor func fixtureAudioLanguages() -> AudioLanguageEnvironment {
  let defaults = UserDefaults(suiteName: "sillies-tests-\(UUID().uuidString)")!
  let preferences = SpeechLanguagePreferences(defaults: defaults)
  preferences.remember(fixtureEnglish)
  return AudioLanguageEnvironment(
    preferences: preferences,
    load: {
      SpeechLanguageCatalog(languages: [fixtureEnglish, fixtureFrench])
    })
}
