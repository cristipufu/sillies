import AppKit
import SilliesDesign
import SilliesDiagnostics
import SilliesModelStore
import SilliesVault
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func everySettingsDestinationFitsTheResizableWindowWithoutLosingNavigation()
  async throws
{
  let domain = "sillies-settings-navigation-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: domain))
  defer { defaults.removePersistentDomain(forName: domain) }
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
  defer { removeTestFile(at: directory) }
  let controller = try CompanionController(
    settings: AppSettings(defaults: defaults),
    services: .init(
      accessibility: .disabled,
      skills: SkillCoordinator(
        vault: SessionVaultStore(directory: directory.appendingPathComponent("Vault")))))
  let speech = try SpeechServices(
    defaults: defaults, modelDirectory: directory.appendingPathComponent("Models"))
  let writing = WritingTools(
    speech: speech, companions: controller,
    services: .init(
      vault: controller.skills.vault, recording: controller.skills, commands: controller.commands,
      reasoning: FixtureReasoning(), appearance: ThemeEnvironment()),
    preferences: DictationPreferences(defaults: defaults))
  let shortcuts = CommandShortcuts(defaults: defaults)
  await speech.models.load()
  let textModels = TextModelsPresentation()
  await textModels.load()
  let appearancePreferences = AppearancePreferences(defaults: defaults)
  await appearancePreferences.load()
  let language = LanguagePreferences(
    defaults: defaults, metadataURL: directory.appendingPathComponent("Languages.json"),
    load: { _ in
      try JSONDecoder().decode(
        [InterfaceLanguage].self,
        from: Data(#"[{"code":"en","language":"English","english":"English"}]"#.utf8))
    })
  language.start()
  let voices = try VoiceServices(
    defaults: defaults, directory: directory.appendingPathComponent("Voices"))
  await voices.models.load()
  let setupFixture = try SetupFixture()
  let setup = setupFixture.makePresentation()
  let suggestions = SetupModelSuggestions(
    text: textModels, voice: voices.models, speech: speech.models)
  await suggestions.load()
  let recorder = DiagnosticRecorder(
    directory: directory.appendingPathComponent("Diagnostics"), enabled: false)
  let diagnostics = DiagnosticsPresentation(
    recorder: recorder, enabled: false, savePreference: { _ in })
  let search = SearchModelsPresentation(
    environment: SearchModelEnvironment(
      store: ModelStore(root: directory.appendingPathComponent("SearchModels")),
      conversations: ConversationLibrary(
        directory: directory.appendingPathComponent("Conversations")),
      vault: controller.skills.vault.library,
      runtime: .init(inference: .init(), executable: directory.appendingPathComponent("unused")),
      selection: .init(id: SearchModelEnvironment.appleID, save: { _ in })))
  await search.downloads.load()
  let previousAppearance = NSApp.appearance
  defer {
    NSApp.appearance = previousAppearance
    writing.stop()
    speech.stop()
    shortcuts.stop()
    textModels.stop()
    voices.models.stop()
    search.stop()
    appearancePreferences.stop()
    language.stop()
    setup.stop()
    setupFixture.close()
  }
  for appearance in [NSAppearance.Name.aqua, .darkAqua] {
    NSApp.appearance = NSAppearance(named: appearance)
    for destination in SettingsDestination.allCases {
      let navigation = SettingsNavigation(destination: destination)
      let view = SettingsView(
        controller: controller, appearance: appearancePreferences, language: language,
        speechModels: speech.models, voiceModels: voices.models, textModels: textModels,
        searchModels: search,
        shortcuts: shortcuts,
        loginItems: LoginItemSettings(), writingTools: writing,
        diagnostics: diagnostics, setup: setup, suggestions: suggestions,
        companionPreferences: setupFixture.preferences,
        actions: .init(openRetention: {}, openMemories: { _ in nil }),
        navigation: navigation)
      try renderSkillInterface(
        view, size: SettingsWindowLayout.minimumSize,
        name: "sillies-settings-\(destination.rawValue)-\(appearance.rawValue)")
      if destination == .companions {
        navigation.showProfile("pogo")
        try renderSkillInterface(
          view, size: SettingsWindowLayout.minimumSize,
          name: "sillies-settings-profile-\(appearance.rawValue)")
      }
    }
  }
  await writing.history.flush()
  await controller.skills.vault.flush()
  await recorder.shutdown()
}
