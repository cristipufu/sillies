import Foundation
import SilliesModelStore
import SilliesTTS

/// Cancels real streaming work, joins it, and verifies that a fresh utterance can complete.
struct VoiceRecoveryBenchmark {
  let registry: TTSModelRegistry
  let manifest: TTSModelManifest
  let request: SpeechSynthesisRequest
  let directory: URL

  func run() async throws {
    do {
      let (events, started) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
      let synthesis = Task {
        defer { started.finish() }
        try await registry.synthesize(request, using: manifest) { _ in started.yield(()) }
      }
      for await _ in events { break }
      let cancelledAt = ContinuousClock.now
      synthesis.cancel()
      switch await synthesis.result {
      case .failure(is CancellationError):
        print("Cancellation joined in \(cancelledAt.duration(to: .now))")
      case .failure(let error): throw error
      case .success: throw TTSError.unavailable("The fixture finished before cancellation.")
      }
      let samples = SampleCollector()
      try await registry.synthesize(request, using: manifest) { await samples.append($0) }
      print(
        try await samples.write(
          to: directory.appendingPathComponent("\(manifest.modelID)-recovery.wav")))
      await registry.stop()
    } catch {
      await registry.stop()
      throw error
    }
  }
}
