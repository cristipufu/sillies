import Foundation
import SilliesAudio
import SilliesCore
import SilliesSpeech
import SilliesSpeechApple

@MainActor
final class SpeechLanguagePreferences {
  private static let preferenceKey = "transcriptionLanguage"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  var selectedIdentifier: String? { defaults.string(forKey: Self.preferenceKey) }

  func selectedIdentifier(for model: SpeechModelDescriptor) -> String? {
    guard !model.isSystemManaged else { return selectedIdentifier }
    return defaults.string(forKey: Self.preferenceKey + "." + model.id)
      ?? (model.capabilities.supportsAutomaticDetection ? SpeechLanguage.automatic.id : nil)
  }

  func remember(_ language: SpeechLanguage) {
    defaults.set(language.id, forKey: Self.preferenceKey)
  }

  func remember(_ language: SpeechLanguage, for model: SpeechModelDescriptor) {
    if model.isSystemManaged {
      remember(language)
    } else {
      defaults.set(language.id, forKey: Self.preferenceKey + "." + model.id)
    }
  }
}

@MainActor
struct AudioLanguageEnvironment {
  let preferences: SpeechLanguagePreferences
  var load: @Sendable () async throws -> SpeechLanguageCatalog = {
    await AppleSpeechLanguageDiscovery.load()
  }

  static var live: AudioLanguageEnvironment {
    AudioLanguageEnvironment(preferences: SpeechLanguagePreferences())
  }
}
