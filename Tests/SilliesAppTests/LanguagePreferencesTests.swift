import AppKit
import SilliesDesign
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

@Test @MainActor func languageRestartKeepsOwnershipWhenCancelledLoadFinishesLate() async throws {
  let suite = "sillies-language-restart-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let loader = SuspendedLanguageLoader()
  let model = LanguagePreferences(
    defaults: defaults, metadataURL: URL(fileURLWithPath: "/unused"),
    load: { _ in try await loader.load() })
  model.start()
  await loader.waitForRequest(1)
  model.stop()
  model.start()
  await loader.waitForRequest(2)
  try await loader.complete(0)
  for _ in 0..<20 { await Task.yield() }
  #expect(model.isLoading)
  #expect(model.languages.isEmpty)
  model.stop()
  await loader.fail(1)
  for _ in 0..<20 { await Task.yield() }
  #expect(!model.isLoading)
  #expect(model.error == nil)
  model.start()
  await loader.waitForRequest(3)
  try await loader.complete(2)
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while model.isLoading, ContinuousClock.now < deadline { await Task.yield() }
  #expect(model.languages.map(\.code) == ["en"])
  #expect(model.error == nil)
}

private actor SuspendedLanguageLoader {
  private var requests: [CheckedContinuation<[InterfaceLanguage], any Error>] = []
  func load() async throws -> [InterfaceLanguage] {
    try await withCheckedThrowingContinuation { requests.append($0) }
  }
  func waitForRequest(_ count: Int) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while requests.count < count, ContinuousClock.now < deadline { await Task.yield() }
    #expect(requests.count == count)
  }
  func complete(_ index: Int) throws {
    let language = try JSONDecoder().decode(
      InterfaceLanguage.self,
      from: Data(#"{"code":"en","language":"English","english":"English"}"#.utf8))
    requests[index].resume(returning: [language])
  }
  func fail(_ index: Int) { requests[index].resume(throwing: CocoaError(.fileReadCorruptFile)) }
}
