import Foundation
import SilliesInference
import SilliesModelStore
import SilliesTTS
import SilliesTextModels

/// Isolated native resources shared by contention and spoken-answer probes.
struct VoiceBenchmarkModels {
  let textManifest: TextModelManifest
  let voiceManifest: TTSModelManifest
  let textStore: ModelStore
  let text: TextModelRegistry
  let voice: TTSModelRegistry
  let directory: URL

  init(arguments: [String]) throws {
    guard arguments.count == 5,
      let textManifest = try TextModelCatalog.bundled().manifests.first(where: {
        $0.modelID == arguments[0]
      }),
      let voiceManifest = try TTSModelCatalog.bundled().manifests.first(where: {
        $0.modelID == arguments[2]
      }),
      let textHelper = ProcessInfo.processInfo.environment["SILLIES_TEXT_HELPER"],
      let voiceHelper = ProcessInfo.processInfo.environment["SILLIES_TTS_HELPER"]
    else { throw TTSError.invalidRequest }
    self.textManifest = textManifest
    self.voiceManifest = voiceManifest
    directory = URL(fileURLWithPath: arguments[4])
    let activity = InferenceActivity()
    textStore = ModelStore(root: URL(fileURLWithPath: arguments[1]))
    text = try TextModelRegistry(
      store: textStore,
      providers: [MLXTextModelProvider(executable: URL(fileURLWithPath: textHelper))],
      activity: activity)
    voice = try TTSModelRegistry(
      store: ModelStore(root: URL(fileURLWithPath: arguments[3])),
      providers: [
        WorkerTTSProvider(
          id: voiceManifest.model.providerID,
          executable: URL(fileURLWithPath: voiceHelper))
      ], activity: activity)
  }

  func stop() async {
    await text.stop()
    await voice.stop()
  }
}
