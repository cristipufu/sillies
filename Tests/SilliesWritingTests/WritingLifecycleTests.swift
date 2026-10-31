import Foundation
import SilliesAudio
import SilliesCore
import SilliesReasoning
import SilliesSpeech
import SilliesWriting
import Testing

@Test @MainActor func isolatedDictationRecoversFinalSpeechBeforeTerminationFlush() async throws {
  let history = RecoveryHistory()
  let destination = WritingDestination()
  let session = DictationCoordinator(
    services: .init(
      capture: .init(
        factory: { _, update in WritingCapture(update: update) },
        loadLanguages: {
          .init(languages: [.init(id: "en-US", name: "English", isInstalled: true)])
        },
        deliver: { action in Task { @MainActor in action() } }),
      text: .init(
        insertion: destination, cleanup: BoundedTextCleanup(), transform: { text, _ in text }),
      context: .init(
        currentApplication: { .init(processID: 42, name: "Editor", bundleIdentifier: nil) },
        vocabularyHints: { [] })),
    preferences: WritingPreferences(), history: history)
  session.start(.hold)
  #expect(session.phase == .preparing)
  try await eventually { session.canFinish }
  await withCheckedContinuation { continuation in
    session.flushForTermination { continuation.resume() }
  }
  #expect(history.flushed)
  #expect(history.results.count == 1)
  #expect(history.results.first?.text == "Ștefan uses API_v2.")
  #expect(history.results.first?.delivery == .needsPaste)
  #expect(await destination.inserted.isEmpty)
  #expect(!session.isBusy)
}

@Test @MainActor func isolatedSelectionFailurePreservesOriginalAndNeverInserts() async throws {
  struct Unavailable: LocalizedError { var errorDescription: String? { "Model unavailable" } }
  let history = RecoveryHistory()
  let destination = WritingDestination()
  let session = SelectionCommandCoordinator(
    history: history,
    services: .init(
      text: .init(
        insertion: destination, cleanup: BoundedTextCleanup(),
        transform: { _, _ in throw Unavailable() }),
      currentApplication: { .init(processID: 42, name: "Editor", bundleIdentifier: nil) }))
  session.start(.shorten)
  try await eventually { !session.isWorking }
  #expect(session.status == "Model unavailable")
  #expect(session.result == nil)
  #expect(history.results.isEmpty)
  #expect(await destination.inserted.isEmpty)
}
