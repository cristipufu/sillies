import Foundation
import SilliesChat
import SilliesInference
import SilliesModelStore
import SilliesTTS
import SilliesVoicePlayback

@MainActor final class VoiceServices {
  private static let preferenceKey = "speechSynthesisModel"
  let environment: VoiceModelEnvironment
  let speech: any ChatSpeechOutput
  let models: VoiceModelsPresentation

  init(defaults: UserDefaults = .standard, directory: URL? = nil) throws {
    let root =
      directory
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Sillies/VoiceModels", isDirectory: true)
    let store = ModelStore(root: root)
    let executable = Bundle.main.bundleURL
      .appendingPathComponent(
        "Contents/Helpers/SilliesTTSInference.app/Contents/MacOS/SilliesTTSInference")
    let providers = ["kokoro", "pocket-tts", "qwen3-tts", "fish-speech"].map {
      WorkerTTSProvider(id: $0, executable: executable)
    }
    let registry = try TTSModelRegistry(store: store, providers: providers, activity: .shared)
    let environment = VoiceModelEnvironment(
      store: store, registry: registry,
      selectedID: defaults.string(forKey: Self.preferenceKey) ?? VoiceModelEnvironment.disabledID,
      savePreference: { defaults.set($0, forKey: Self.preferenceKey) })
    self.environment = environment
    speech = ChatSpeechPlayer(models: environment, playback: VoicePlayback())
    models = VoiceModelsPresentation(environment: environment)
  }
}
