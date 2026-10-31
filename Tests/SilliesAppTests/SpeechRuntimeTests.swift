import AVFoundation
import Foundation
import SilliesCore
import SilliesModelStore
import SilliesSpeech
import Testing

@testable import SilliesApp

@Test func speechRuntimeSharesPreparationAndCancellationDoesNotStopAnotherConsumer() async throws {
  let provider = PreparationProbe()
  let store = ModelStore(
    root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
  let registry = try SpeechRuntimeRegistry(store: store, providers: [provider])
  let first = Task { try await registry.prepare(SpeechModelDescriptor.apple.id) }
  while await provider.starts == 0 { await Task.yield() }
  let second = Task { try await registry.prepare(SpeechModelDescriptor.apple.id) }
  // The second request joins before the first preparation finishes.
  try await Task.sleep(for: .milliseconds(10))
  first.cancel()
  let runtime = try await second.value
  do {
    _ = try await first.value
    Issue.record("Cancelled consumer received a model")
  } catch is CancellationError {}
  #expect(await provider.starts == 1)
  #expect(await provider.observedMainThread == false)
  let same = try await registry.prepare(SpeechModelDescriptor.apple.id)
  #expect(runtime === same)
}

private actor PreparationProbe: SpeechProvider, PreparedSpeechModel {
  nonisolated let id = "apple"
  private(set) var starts = 0
  private(set) var observedMainThread = false
  func prepare(_ request: SpeechPreparation) async throws -> any PreparedSpeechModel {
    starts += 1
    observeThread()
    try await Task.sleep(for: .milliseconds(100))
    return self
  }
  private func observeThread() { observedMainThread = Thread.isMainThread }
  func makeChannel(_ request: SpeechChannelRequest) async throws -> any LocalSpeechChannel {
    throw SpeechError.unavailable("This fixture only prepares models.")
  }
}

@Test @MainActor func downloadableSpeechDefaultsToAutomaticWithoutChangingAppleLanguage() throws {
  let suite = "sillies-speech-preferences-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let preferences = SpeechLanguagePreferences(defaults: defaults)
  let english = SpeechLanguage(id: "en-US", name: "English", isInstalled: true)
  preferences.remember(english)
  let whisper = try SpeechModelCatalog.bundled().manifest(for: "whisper-turbo").model
  #expect(preferences.selectedIdentifier(for: whisper) == "auto")
  preferences.remember(.init(id: "ro", name: "Romanian", isInstalled: true), for: whisper)
  #expect(preferences.selectedIdentifier(for: whisper) == "ro")
  #expect(preferences.selectedIdentifier == "en-US")
}
