import Foundation
import SilliesSpeech

struct NemotronSpeechModel: PreparedSpeechModel {
  private let engines: SpeechEnginePool<String>

  init(directory: URL, preparedEngine: NemotronStreamingEngine) {
    engines = SpeechEnginePool(prepared: ("auto", preparedEngine)) { code in
      let engine = NemotronStreamingEngine()
      try await engine.load(
        directory, language: .init(id: code, name: code, isInstalled: true))
      return engine
    }
  }

  func makeChannel(_ request: SpeechChannelRequest) async throws -> any LocalSpeechChannel {
    let lease = try await engines.acquire(for: Self.code(request.language))
    do {
      try Task.checkCancellation()
      let channel = try WindowSpeechChannel(
        engine: SpeechInferenceScheduler(engine: lease), request: request,
        configuration: NemotronRecognitionConfiguration.channel)
      return LeasedSpeechChannel(channel: channel, lease: lease)
    } catch {
      await lease.release()
      throw error
    }
  }

  func validate() async throws {
    let lease = try await engines.acquire(for: Self.code(.automatic))
    do {
      try await WindowSpeechModel(engine: SpeechInferenceScheduler(engine: lease)).validate()
      await lease.release()
    } catch {
      await lease.release()
      throw error
    }
  }

  private static func code(_ language: SpeechLanguage) -> String {
    language.isAutomatic ? "auto" : language.locale.language.languageCode?.identifier ?? language.id
  }
}
