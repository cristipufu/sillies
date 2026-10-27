import Foundation

struct SpeechLanguage: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let isInstalled: Bool
  let supportsNotes: Bool

  var locale: Locale { Locale(identifier: id) }
}

struct SpeechLanguageCatalog: Sendable {
  let languages: [SpeechLanguage]

  var installed: [SpeechLanguage] { languages.filter(\.isInstalled) }

  func preferredLanguage(savedIdentifier: String?, deviceLocale: Locale = .current)
    -> SpeechLanguage?
  {
    let preferred = Locale(identifier: savedIdentifier ?? deviceLocale.identifier)
    if let exact = installed.first(where: {
      $0.locale.language.languageCode == preferred.language.languageCode
        && $0.locale.language.region == preferred.language.region
        && $0.locale.language.script == preferred.language.script
    }) {
      return exact
    }
    return installed.first { $0.locale.language.languageCode == preferred.language.languageCode }
  }
}
