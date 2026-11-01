import Foundation
import SilliesModelStore
import SilliesTTS

/// Exercises voice changes in one live runtime, including returning to a previous voice.
enum VoicePreparationBenchmark {
  static func run(registry: TTSModelRegistry, manifest: TTSModelManifest) async throws {
    guard let first = manifest.model.voices.first, let last = manifest.model.voices.last else {
      throw TTSError.unsupportedVoice
    }
    do {
      for voice in [first, last, first] {
        let request = SpeechSynthesisRequest(
          text: "Hello there!", voiceID: voice.id, language: "en")
        let start = ProcessInfo.processInfo.systemUptime
        guard
          try await registry.prepareVoiceIfPossible(
            request.voice, using: manifest, conversationID: UUID())
        else { throw TTSError.busy }
        let prepared = ProcessInfo.processInfo.systemUptime - start
        let samples = SampleCollector()
        try await registry.synthesize(request, using: manifest) { await samples.append($0) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
          "sillies-voice-switch")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let report = try await samples.write(
          to: directory.appendingPathComponent(manifest.modelID + "-" + voice.id + ".wav"))
        print("VOICE \(voice.id): preparation=\(prepared)s; \(report)")
      }
      await registry.stop()
    } catch {
      await registry.stop()
      throw error
    }
  }
}
