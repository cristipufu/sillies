import Foundation
import SilliesAudioTestSupport

@testable import SilliesApp
@testable import SilliesAudio

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
