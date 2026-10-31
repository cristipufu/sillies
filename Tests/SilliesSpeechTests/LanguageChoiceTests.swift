import Foundation
import SilliesSpeech
import Testing

@Test func explicitLanguageChoicesSurviveProviderChangesWithoutSilentlyChangingLanguage() {
  let catalog = SpeechLanguageCatalog(languages: [
    .automatic, .init(id: "en", name: "English", isInstalled: true),
    .init(id: "ro", name: "Romanian", isInstalled: false),
  ])
  #expect(catalog.installedLanguage(matching: "en-US")?.id == "en")
  #expect(catalog.installedLanguage(matching: "ro-RO") == nil)
  #expect(catalog.installedLanguage(matching: "auto") == .automatic)
}

@Test func automaticChoiceUsesDeviceLanguageWhenTheProviderDoesNotOfferDetection() {
  let english = SpeechLanguage(id: "en-US", name: "English", isInstalled: true)
  let catalog = SpeechLanguageCatalog(languages: [english])
  #expect(
    catalog.preferredLanguage(savedIdentifier: "auto", deviceLocale: Locale(identifier: "en-GB"))
      == english)
  #expect(catalog.installedLanguage(matching: "ro-RO") == nil)
}
