import AppKit
import SilliesCore
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func writingLibraryWindowsFitTheirMinimumSizesInBothAppearances() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let history = WritingHistory(directory: directory.appendingPathComponent("Writing"))
  await history.load()
  history.save(
    .init(
      originalText: "Ștefan will review API_v2 at 16:30.",
      text: String(repeating: "Ștefan will review API_v2 at 16:30. ", count: 500),
      applicationName: "Editor", notice: "The destination changed. Your words are ready to copy."))
  let vault = SessionVaultStore(directory: directory.appendingPathComponent("Vault"))
  await vault.waitUntilLoaded()
  let previousAppearance = NSApp.appearance
  defer { NSApp.appearance = previousAppearance }
  for appearance in [NSAppearance.Name.aqua, .darkAqua] {
    NSApp.appearance = NSAppearance(named: appearance)
    try renderSkillInterface(
      WritingHistoryView(model: history, copy: { _ in }, openText: { _ in }),
      size: .init(width: 560, height: 400), name: "sillies-recent-writing-\(appearance.rawValue)")
    try renderSkillInterface(
      StashPickerView(vault: vault, paste: PasteBackCoordinator(), choose: { _ in }, close: {}),
      size: .init(width: 560, height: 440), name: "sillies-stash-picker-\(appearance.rawValue)")
    try renderSkillInterface(
      VaultRetentionView(vault: vault), size: .init(width: 470, height: 460),
      name: "sillies-retention-\(appearance.rawValue)")
  }
  await history.flush()
  await vault.flush()
}

@Test @MainActor func writingReservesOneAvailableMascotUntilReleased() throws {
  let domain = "sillies-writing-companion-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: domain))
  defer { defaults.removePersistentDomain(forName: domain) }
  let settings = AppSettings(defaults: defaults)
  settings.enabledCharacters = ["mochi", "kiko"]
  settings.followsWindows = false
  settings.reduceMotion = true
  let controller = try CompanionController(
    settings: settings, services: .init(accessibility: .disabled))
  controller.start()
  defer { controller.stop() }
  #expect(controller.hasAvailableWritingCompanion)
  let companion = try #require(controller.beginWritingIndicator())
  #expect(["Mochi", "Kiko"].contains(companion.name))
  #expect(controller.beginWritingIndicator()?.windowNumber == companion.windowNumber)
  controller.endWritingIndicator()
  #expect(controller.hasAvailableWritingCompanion)
  settings.enabledCharacters = []
  #expect(!controller.hasAvailableWritingCompanion)
  #expect(controller.beginWritingIndicator() == nil)
}
