import AppKit
import SilliesAudio
import SilliesCore
import SilliesModelStore
import SilliesReasoning
import SilliesSpeechApple

@testable import SilliesApp

/// Test-only defaults. Production constructors require their service owners explicitly.
struct FixtureReasoning: LocalReasoning {
  func availabilityNotice(localeIdentifier: String?) async -> String? { "Fixture reasoning" }
  func notes(
    for text: String, kind: CompanionSkillKind, fallback: String, localeIdentifier: String?
  ) async -> LocalNotes {
    let result = await SessionSummaryWorker.summarize(text: text, fallbackContext: fallback)
    return LocalNotes(
      summary: result.summary, actions: result.actionItems, provenance: .init(source: .extracted))
  }
  func suggestion(source: String, elapsed: TimeInterval, localeIdentifier: String?) async
    -> MeetingSuggestion?
  { nil }
  func transform(_ text: String, operation: LocalTextOperation) async throws -> String { text }
}

extension SessionVaultStore {
  convenience init(
    directory: URL? = nil, pasteboard: NSPasteboard = .general, defaults: UserDefaults = .standard
  ) {
    self.init(
      directory: directory
        ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
      pasteboard: pasteboard, defaults: defaults,
      notesGenerator: { record in
        await FixtureReasoning().notes(
          for: record.primaryText, kind: record.kind, fallback: record.summary,
          localeIdentifier: record.languageIdentifier)
      })
  }
}

extension SkillCoordinator {
  convenience init(
    vault: SessionVaultStore,
    audioFactory: @escaping SessionAudioCaptureFactory = {
      AudioTranscriptionService(
        configuration: $0, speech: AppleSpeechProvider.makeChannel, onUpdate: $1)
    }, audioLanguages: AudioLanguageEnvironment = .live,
    snapshotLoader: @escaping SnapshotLoader = { ids, top in
      await WindowTargetMetadata.shared.snapshots(for: ids, primaryScreenTop: top)
    }
  ) {
    self.init(
      vault: vault,
      audio: .init(
        captureFactory: audioFactory, languages: audioLanguages, reasoning: FixtureReasoning()),
      snapshotLoader: snapshotLoader)
  }
}

extension CompanionServices {
  init(
    accessibility: WorkspaceTracker.Accessibility = .enabled,
    eventProducers: [any WorkspaceEventProducer] = []
  ) {
    self.init(
      accessibility: accessibility, skills: SkillCoordinator(vault: SessionVaultStore()),
      eventProducers: eventProducers)
  }
}

extension CompanionController {
  convenience init(settings: AppSettings, assets: CompanionAssets = .init()) throws {
    try self.init(settings: settings, assets: assets, services: .init())
  }
}

extension TextModelsPresentation {
  convenience init() {
    self.init(
      environment: TextModelEnvironment(
        store: ModelStore(
          root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        preference: .init(selectedID: "apple", save: { _ in }), providers: []))
  }
}
