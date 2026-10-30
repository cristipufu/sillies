import Foundation
import SilliesAudio

@MainActor
final class SpeechLanguagePreferences {
  private static let preferenceKey = "transcriptionLanguage"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  var selectedIdentifier: String? { defaults.string(forKey: Self.preferenceKey) }

  func remember(_ language: SpeechLanguage) {
    defaults.set(language.id, forKey: Self.preferenceKey)
  }
}

@MainActor
struct AudioLanguageEnvironment {
  let preferences: SpeechLanguagePreferences
  var load: @Sendable () async -> SpeechLanguageCatalog = { await SpeechLanguageDiscovery.load() }

  static var live: AudioLanguageEnvironment {
    AudioLanguageEnvironment(preferences: SpeechLanguagePreferences())
  }
}
