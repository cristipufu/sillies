import AppKit
import Testing

@testable import SilliesApp

@Test @MainActor func languageSelectionPersistsWithoutChangingRecognitionOrRestartingSessions()
  async throws
{
  let suite = "sillies-language-preferences-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {
    defaults.removePersistentDomain(forName: suite)
    removeTestFile(at: file)
  }
  let metadata = [
    ["code": "en", "language": "English", "english": "English"],
    ["code": "cy", "language": "Cymraeg", "english": "Welsh"],
  ]
  try JSONSerialization.data(withJSONObject: metadata).write(to: file)
  defaults.set("ja", forKey: "dictationLanguage")
  let model = LanguagePreferences(defaults: defaults, metadataURL: file)
  model.start()
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while model.languages.isEmpty, model.error == nil, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  defer { model.stop() }
  #expect(model.languages.count == 2)
  #expect(!model.requiresRestart)
  model.select("cy")
  #expect(model.selectedID == "cy")
  #expect(model.requiresRestart)
  #expect(defaults.stringArray(forKey: "AppleLanguages") == ["cy"])
  #expect(defaults.string(forKey: "dictationLanguage") == "ja")
  model.select("../../invalid")
  #expect(model.selectedID == "cy")
  let reopened = LanguagePreferences(defaults: defaults, metadataURL: file)
  #expect(reopened.selectedID == "cy")
  #expect(!reopened.requiresRestart)
  model.select(LanguagePreferences.systemID)
  #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
  #expect(!model.requiresRestart)
}
