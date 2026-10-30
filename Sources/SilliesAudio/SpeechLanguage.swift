import Foundation

package struct SpeechLanguage: Identifiable, Equatable, Sendable {
  package let id: String
  package let name: String
  package let isInstalled: Bool
  package let supportsNotes: Bool

  package init(id: String, name: String, isInstalled: Bool, supportsNotes: Bool) {
    self.id = id
    self.name = name
    self.isInstalled = isInstalled
    self.supportsNotes = supportsNotes
  }

  package var locale: Locale { Locale(identifier: id) }
}

package struct SpeechLanguageCatalog: Sendable {
  package let languages: [SpeechLanguage]

  package init(languages: [SpeechLanguage]) { self.languages = languages }

  package var installed: [SpeechLanguage] { languages.filter(\.isInstalled) }

  package func preferredLanguage(savedIdentifier: String?, deviceLocale: Locale = .current)
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
