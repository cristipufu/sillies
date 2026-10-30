import Foundation
import SilliesAudio
import SilliesCore
import SilliesDiarizationNemotron
import SilliesModelStore
import SilliesSpeech
import SilliesSpeechApple
import SilliesSpeechParakeet
import SilliesSpeechWhisper

@MainActor
final class SpeechServices {
  let models: SpeechModelsPresentation
  private let registry: SpeechRuntimeRegistry
  private let preferences: SpeechLanguagePreferences
  private var startup: Task<Void, Never>?

  init(defaults: UserDefaults = .standard) {
    let support =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support")
    let root = support.appendingPathComponent("Sillies/SpeechModels", isDirectory: true)
    let store = ModelStore(root: root)
    let registry = SpeechRuntimeRegistry(
      store: store,
      providers: [AppleSpeechProvider(), WhisperSpeechProvider(), ParakeetSpeechProvider()],
      diarizationProviders: [NemotronDiarizationProvider()])
    self.registry = registry
    preferences = SpeechLanguagePreferences(defaults: defaults)
    let checker = ModelUpdateChecker(
      store: store, location: root.appendingPathComponent("model-updates.json"))
    models = SpeechModelsPresentation(
      store: store, registry: registry, defaults: defaults,
      updates: ModelUpdatesPresentation(checker: checker, registry: registry, defaults: defaults))
  }

  func start() {
    guard startup == nil else { return }
    startup = Task { [models] in await models.load() }
  }

  var languages: AudioLanguageEnvironment {
    AudioLanguageEnvironment(preferences: preferences) { [models, registry] in
      let id = await models.selectedModelID
      let speakerID = await models.diarizationModelID
      var catalog = try await registry.languages(for: id)
      if let speakerID {
        catalog.diarizationModel = try await registry.currentManifest(speakerID).model
      }
      return catalog
    }
  }

  var captureFactory: SessionAudioCaptureFactory {
    { [registry] configuration, update in
      let preparation = SpeechCapturePreparation(
        registry: registry, model: configuration.model)
      let diarization = Self.diarizationFactory(
        model: configuration.diarizationModel, registry: registry)
      return AudioTranscriptionService(
        configuration: configuration,
        speech: { language, output, failure in
          try await preparation.makeChannel(language: language, output: output, failure: failure)
        }, diarization: diarization, onUpdate: update)
    }
  }

  nonisolated private static func diarizationFactory(
    model: SpeechModelDescriptor?, registry: SpeechRuntimeRegistry
  ) -> SpeakerDiarizationFactory.Make? {
    guard let model else { return nil }
    return { request in
      let runtime = try await registry.prepare(model)
      return try await runtime.makeChannel(request)
    }
  }

  func stop() {
    startup?.cancel()
    startup = nil
    models.stop()
    Task { await registry.cancelPreparation() }
  }
}
