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
  let vocabulary: VocabularyPreferences
  private let dictationRuntime: DictationRuntimeCache
  private let registry: SpeechRuntimeRegistry
  private let preferences: SpeechLanguagePreferences
  private var startup: Task<Void, Never>?

  init(defaults: UserDefaults = .standard, modelDirectory: URL? = nil) throws {
    vocabulary = VocabularyPreferences(defaults: defaults)
    let support =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support")
    let root =
      modelDirectory ?? support.appendingPathComponent("Sillies/SpeechModels", isDirectory: true)
    let store = ModelStore(root: root)
    let registry = try SpeechRuntimeRegistry(
      store: store,
      providers: [AppleSpeechProvider(), WhisperSpeechProvider(), ParakeetSpeechProvider()],
      diarizationProviders: [NemotronDiarizationProvider()])
    self.registry = registry
    dictationRuntime = DictationRuntimeCache(registry: registry)
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
    { [registry, vocabulary, dictationRuntime] configuration, update in
      var configuration = configuration
      let dictionary = vocabulary.snapshot()
      configuration.dictionary = dictionary
      var context = configuration.recognitionContext
      context.vocabulary = dictionary.hints
      let preparation = SpeechCapturePreparation(
        registry: registry, model: configuration.model, context: context)
      let recognitionContext = context
      let model = configuration.model
      let diarization = Self.diarizationFactory(
        model: configuration.diarizationModel, registry: registry)
      return AudioTranscriptionService(
        configuration: configuration,
        speech: { language, output, failure in
          if recognitionContext.priority == .interactive {
            var request = SpeechChannelRequest(language: language, output: output, failure: failure)
            request.context = recognitionContext
            let channelRequest = request
            return try await InteractiveSpeechChannel.make {
              try await dictationRuntime.makeChannel(model: model, request: channelRequest)
            }
          }
          return try await preparation.makeChannel(
            language: language, output: output, failure: failure)
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
    Task { await dictationRuntime.stop() }
  }
  func releaseInteractiveResources() { Task { await dictationRuntime.stop() } }
}
