import Foundation
import SilliesAudio
import SilliesCore
import SilliesDiagnostics
import SilliesDiarizationNemotron
import SilliesInference
import SilliesModelStore
import SilliesSpeech
import SilliesSpeechApple
import SilliesSpeechNemotron
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
  private let diagnostics: DiagnosticSink

  init(
    defaults: UserDefaults = .standard, modelDirectory: URL? = nil,
    diagnostics: DiagnosticSink = .disabled
  ) throws {
    self.diagnostics = diagnostics
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
      providers: [
        AppleSpeechProvider(), WhisperSpeechProvider(), ParakeetSpeechProvider(),
        NemotronSpeechProvider(),
      ],
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
    { [registry, vocabulary, dictationRuntime, diagnostics] configuration, update in
      let selected = configuration.model
      let operation = UUID()
      diagnostics.record(
        .init(.recognition, .modelSelected, operation: operation)
          .using(model: selected.id, provider: selected.providerID)
      )
      var configuration = configuration
      let dictionary = vocabulary.snapshot()
      configuration.dictionary = dictionary
      var context = configuration.recognitionContext
      context.vocabulary = dictionary.hints
      let preparation = SpeechCapturePreparation(
        registry: registry, model: configuration.model, context: context,
        backlogDirectory: configuration.recordingURL?.deletingLastPathComponent())
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
        }, diarization: diarization, applicationIdentity: NativeApplicationAudioIdentity.verify,
        events: .init(
          update: { event in
            CaptureDiagnostics.recordRecognition(event, operation: operation, sink: diagnostics)
            update(event)
          },
          reportOverload: {
            CaptureDiagnostics.record($0, operation: operation, sink: diagnostics)
          },
          lifecycle: { CaptureDiagnostics.record($0, operation: operation, sink: diagnostics) }
        ))
    }
  }

  func conversationCaptureFactory(reference: VoicePlaybackReference) -> ConversationCaptureFactory {
    { [dictationRuntime, vocabulary, diagnostics] configuration, update in
      let selected = configuration.model
      let operation = UUID()
      diagnostics.record(
        .init(.recognition, .modelSelected, operation: operation)
          .using(model: selected.id, provider: selected.providerID)
      )
      let dictionary = vocabulary.snapshot()
      var configuration = configuration
      configuration.dictionary = dictionary
      let model = configuration.model
      return VoiceConversationCapture(
        configuration: configuration, reference: reference,
        speech: .init(
          warm: {
            diagnostics.record(.init(.recognition, .started, operation: operation))
            do {
              try await InferenceActivity.shared.prepareSpeechRuntime {
                try await dictationRuntime.prepare(model: model)
              }
              diagnostics.record(.init(.recognition, .completed, operation: operation))
            } catch {
              diagnostics.record(
                .init(
                  .recognition, error is CancellationError ? .cancelled : .failed,
                  operation: operation
                ).failing(error))
              throw error
            }
          },
          makeChannel: { language, output, failure in
            var request = SpeechChannelRequest(language: language, output: output, failure: failure)
            request.context = .init(vocabulary: dictionary.hints, priority: .interactive)
            let channelRequest = request
            return try await InteractiveSpeechChannel.make {
              try await dictationRuntime.makeChannel(model: model, request: channelRequest)
            }
          }), update: update)
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
