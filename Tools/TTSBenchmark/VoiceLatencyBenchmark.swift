import Foundation
import SilliesModelStore
import SilliesTTS

/// Separates process/model preparation from phrase generation using the same installed weights.
struct VoiceLatencyBenchmark {
  let registry: TTSModelRegistry
  let manifest: TTSModelManifest
  let request: SpeechSynthesisRequest
  let directory: URL

  func run() async throws {
    do {
      try await measure("cold")
      await registry.stop()
      let started = ContinuousClock.now
      guard
        try await registry.prepareVoiceIfPossible(
          request.voice, using: manifest, conversationID: UUID())
      else { throw TTSError.busy }
      print("\(manifest.model.name): preparation \(started.duration(to: .now))")
      try await measure("prepared")
      try await measure("reused")
      await registry.stop()
    } catch {
      await registry.stop()
      throw error
    }
  }

  private func measure(_ label: String) async throws {
    let samples = SampleCollector()
    let started = ContinuousClock.now
    try await registry.synthesize(request, using: manifest) { audio in await samples.append(audio) }
    let elapsed = started.duration(to: .now)
    let report = try await samples.write(
      to: directory.appendingPathComponent("\(manifest.modelID)-\(label).wav"))
    print("\(manifest.model.name) \(label): \(report); synthesis \(elapsed)")
  }
}
