import AppKit
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
  let speech = SpeechServices(
    defaults: defaults, modelDirectory: directory.appendingPathComponent("Models"))
  let writing = WritingTools(
    speech: speech, controller: controller, preferences: DictationPreferences(defaults: defaults))
  let shortcuts = CommandShortcuts(defaults: defaults)
  await speech.models.load()
  let textModels = TextModelsPresentation()
  await textModels.load()
  let previousAppearance = NSApp.appearance
  defer {
    NSApp.appearance = previousAppearance
    writing.stop()
    speech.stop()
    shortcuts.stop()
  }
  for appearance in [NSAppearance.Name.aqua, .darkAqua] {
    NSApp.appearance = NSAppearance(named: appearance)
    for destination in SettingsDestination.allCases {
      let view = SettingsView(
        controller: controller, speechModels: speech.models, textModels: textModels,
        shortcuts: shortcuts,
        loginItems: LoginItemSettings(), writingTools: writing, destination: destination)
      try renderSkillInterface(
        view, size: SettingsWindowLayout.minimumSize,
        name: "sillies-settings-\(destination.rawValue)-\(appearance.rawValue)")
    }
  }
  await writing.dictation.history.flush()
  await controller.skills.vault.flush()
}
