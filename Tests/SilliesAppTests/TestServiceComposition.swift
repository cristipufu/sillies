import AppKit
import SilliesAudio
import SilliesCore
import SilliesModelStore
import SilliesReasoning
import SilliesSpeechApple

@testable import SilliesApp

/// Test-only defaults. Production constructors require their service owners explicitly.
struct FixtureReasoning: LocalReasoning {
  var availability: @Sendable (String?) async -> String? = { _ in "Fixture reasoning" }
  func availabilityNotice(localeIdentifier: String?) async -> String? {
    await availability(localeIdentifier)
  }
  func notes(for request: LocalNotesRequest) async -> LocalNotes {
    let result = await SessionSummaryWorker.summarize(
      text: request.source, fallbackContext: request.fallback)
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
      notesGenerator: { input in
        await FixtureReasoning().notes(
          for: .init(
            source: input.record.primaryText, kind: input.record.kind,
            fallback: input.record.summary,
            personalNotes: input.personalNotes, localeIdentifier: input.record.languageIdentifier))
      })
  }
}

extension SkillCoordinator {
  convenience init(
    vault: SessionVaultStore,
    audioFactory: @escaping SessionAudioCaptureFactory = {
      AudioTranscriptionService(
        configuration: $0, speech: AppleSpeechProvider.makeChannel, events: .init(update: $1))
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
    skills: SkillCoordinator = SkillCoordinator(vault: SessionVaultStore()),
    eventProducers: [any WorkspaceEventProducer] = []
  ) {
    self.init(
      accessibility: accessibility, skills: skills,
      appearance: ThemeEnvironment(),
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
