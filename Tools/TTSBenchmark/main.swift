import Foundation
import SilliesInference
import SilliesModelStore
import SilliesTTS

/// Bounded, opt-in real-model check. Normal tests use injected runtimes and never download weights.
@main enum TTSBenchmark {
  static func main() async {
    do { try await run() } catch {
      fputs("Voice model check failed: \(error.localizedDescription)\n", stderr)
      exit(EXIT_FAILURE)
    }
  }

  private static func run() async throws {
    let arguments = CommandLine.arguments
    guard [4, 6].contains(arguments.count), ["install", "run", "latency"].contains(arguments[1])
    else {
      fputs(
        "Usage: TTSBenchmark install|run|latency MODEL_ID MODEL_DIRECTORY [LANGUAGE TEXT]\n", stderr
      )
      exit(EXIT_FAILURE)
    }
    guard
      let manifest = try TTSModelCatalog.bundled().manifests.first(where: {
        $0.modelID == arguments[2]
      })
    else { throw TTSError.unavailable("Unknown voice model.") }
    let directory = URL(fileURLWithPath: arguments[3])
    let store = ModelStore(root: directory)
    if arguments[1] == "install" {
      try await store.install(manifest) { _ in }
      print("Verified installation: \(manifest.model.name)")
      return
    }
    let executable =
      ProcessInfo.processInfo.environment["SILLIES_TTS_HELPER"].map {
        URL(fileURLWithPath: $0)
      }
      ?? URL(fileURLWithPath: arguments[0]).deletingLastPathComponent()
      .appendingPathComponent("SilliesTTSInference")
    let registry = try TTSModelRegistry(
      store: store,
      providers: [WorkerTTSProvider(id: manifest.model.providerID, executable: executable)],
      activity: InferenceActivity())
    let samples = SampleCollector()
    let started = ContinuousClock.now
    let language = arguments.count == 6 ? arguments[4] : "en"
    let passage =
      arguments.count == 6
      ? arguments[5] : "Hello! I’m your little window companion. What’s on your mind?"
    guard let voice = manifest.model.voices.first else { throw TTSError.unsupportedVoice }
    if arguments[1] == "latency" {
      try await VoiceLatencyBenchmark(
        registry: registry, manifest: manifest,
        request: .init(text: passage, voiceID: voice.id, language: language), directory: directory
      ).run()
      return
    }
    do {
      try await registry.synthesize(
        .init(text: passage, voiceID: voice.id, language: language),
        using: manifest
      ) { audio in await samples.append(audio) }
      await registry.stop()
      let report = try await samples.write(
        to: directory.appendingPathComponent(manifest.modelID + ".wav"))
      print("\(manifest.model.name): \(report); elapsed \(started.duration(to: .now))")
    } catch {
      await registry.stop()
      throw error
    }
  }
}
