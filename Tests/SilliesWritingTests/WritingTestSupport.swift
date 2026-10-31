import Foundation
import SilliesAudio
import SilliesCore
import SilliesReasoning
import SilliesSpeech
import SilliesWriting
import Testing

/// These fixtures compile without importing the app, native UI, or persistence.
@MainActor final class RecoveryHistory: WritingHistoryRecording {
  var persistence = WritingHistoryPersistence.saved
  func retry() { persistence = .saved }
  var results: [WritingResult] = []
  var flushed = false
  func save(_ result: WritingResult) {
    results.removeAll { $0.id == result.id }
    results.append(result)
  }
  func flush(
    completion: @escaping @MainActor @Sendable (Result<Void, WritingHistoryFailure>) -> Void
  ) {
    flushed = true
    completion(.success(()))
  }
}

@MainActor final class WritingPreferences: WritingPreferencesReading {
  var style = DictationOutputStyle.verbatim
  var languageIdentifier = "en-US"
}

actor WritingDestination: TextInserting {
  var inserted: [String] = []
  var released = 0
  func capture(_ application: FrontmostApplication) -> TextDestination {
    .init(id: UUID(), application: application, selection: "A source sentence.")
  }
  func insert(_ text: String, into destination: TextDestination) {
    inserted.append(text)
  }
  func release(_ destination: TextDestination) { released += 1 }
}

final class WritingCapture: SessionAudioCapture {
  let update: @Sendable (AudioCaptureUpdate) -> Void
  init(update: @escaping @Sendable (AudioCaptureUpdate) -> Void) { self.update = update }
  func start() { update(.capturing("Microphone")) }
  func pause() {}
  func resume() {}
  func changeLanguage(_ language: SpeechLanguage) {}
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    var result = AudioCaptureResult(
      transcript: "Ștefan uses API_v2.", recordingURL: nil, duration: 2, failure: nil)
    result.segments = [
      .init(sequence: 0, source: "You", start: 0, end: 2, text: "Ștefan uses API_v2.")
    ]
    completion(result)
  }
}

@MainActor func eventually(_ condition: () -> Bool) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: .seconds(2))
  while !condition(), clock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
  try #require(condition())
}

@MainActor struct WritingTestConfiguration {
  var preferences = WritingPreferences()
  var loadLanguages: @Sendable () async throws -> SpeechLanguageCatalog = {
    .init(languages: [.init(id: "en-US", name: "English", isInstalled: true)])
  }
  var factory: SessionAudioCaptureFactory = { _, update in WritingCapture(update: update) }
  var deliver: AudioSessionUpdateDelivery.Schedule = { action in Task { @MainActor in action() } }
  var transform: WritingTextServices.Transform = { text, _ in text }
}
@MainActor func testDictation(
  insertion: any TextInserting, history: RecoveryHistory,
  configuration: WritingTestConfiguration = .init()
) -> DictationCoordinator {
  DictationCoordinator(
    services: .init(
      capture: .init(
        factory: configuration.factory, loadLanguages: configuration.loadLanguages,
        deliver: configuration.deliver),
      text: .init(
        insertion: insertion, cleanup: BoundedTextCleanup(), transform: configuration.transform),
      context: .init(
        currentApplication: { .init(processID: 42, name: "Editor", bundleIdentifier: nil) },
        vocabularyHints: { [] })),
    preferences: configuration.preferences, history: history)
}
