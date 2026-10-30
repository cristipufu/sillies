import Foundation
import FoundationModels
@preconcurrency import Speech

/// Queries system capabilities off the UI thread. Discovery never installs speech assets.
package enum SpeechLanguageDiscovery {
  package static func load() async -> SpeechLanguageCatalog {
    guard SpeechTranscriber.isAvailable else { return SpeechLanguageCatalog(languages: []) }
    let supported = await SpeechTranscriber.supportedLocales
    let installed = Set(await SpeechTranscriber.installedLocales.map(\.identifier))
    let languages = supported.map { locale in
      SpeechLanguage(
        id: locale.identifier,
        name: Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier,
        isInstalled: installed.contains(locale.identifier),
        supportsNotes: SystemLanguageModel.default.supportsLocale(locale))
    }
    return SpeechLanguageCatalog(
      languages: languages.sorted {
        $0.name.localizedStandardCompare($1.name) == .orderedAscending
      })
  }
}
