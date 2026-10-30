import Foundation
import SilliesCore

package struct SpeechLanguage: Identifiable, Equatable, Sendable {
  package let id: String
  package let name: String
  package let isInstalled: Bool

  package init(id: String, name: String, isInstalled: Bool) {
    self.id = id
    self.name = name
    self.isInstalled = isInstalled
  }

  package var locale: Locale { Locale(identifier: id) }
  package var isAutomatic: Bool { id == Self.automatic.id }
  package static let automatic = SpeechLanguage(
    id: "auto", name: "Detect automatically", isInstalled: true)
}

package struct SpeechLanguageCatalog: Sendable {
  package let languages: [SpeechLanguage]
  package let model: SpeechModelDescriptor
  package var diarizationModel: SpeechModelDescriptor?

  package init(languages: [SpeechLanguage], model: SpeechModelDescriptor = .apple) {
    self.languages = languages
    self.model = model
  }

  package var installed: [SpeechLanguage] { languages.filter(\.isInstalled) }

  package func preferredLanguage(savedIdentifier: String?, deviceLocale: Locale = .current)
    -> SpeechLanguage?
  {
    if savedIdentifier == SpeechLanguage.automatic.id, installed.contains(.automatic) {
      return .automatic
    }
    let preferred = Locale(identifier: savedIdentifier ?? deviceLocale.identifier)
    if let exact = installed.first(where: {
      $0.locale.language.languageCode == preferred.language.languageCode
        && $0.locale.language.region == preferred.language.region
        && $0.locale.language.script == preferred.language.script
    }) {
      return exact
    }
    return installed.first { $0.locale.language.languageCode == preferred.language.languageCode }
      ?? installed.first { $0.isAutomatic }
  }
}
