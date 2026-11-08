import Foundation
import SilliesModelStore
import SilliesTTS
import SilliesVibeVoice

struct VibeVoiceTTSModel: NativeTTSModel {
  private let engine = VibeVoiceSpeechEngine()
  private let directory: URL

  init(configuration: TTSPreparation) throws {
    guard configuration.variant == "realtime-0.5b-8bit" else { throw TTSError.invalidRequest }
    directory = configuration.directory
  }

  func prepareVoice(_ voice: SpeechVoice) async throws {
    do {
      try await engine.prepare(directory: directory, voiceID: voice.id)
    } catch is CancellationError { throw CancellationError() } catch let error as TTSError {
      throw error
    } catch { throw ModelStoreError.invalidArtifact("VibeVoice") }
  }

  func synthesize(_ request: SpeechSynthesisRequest, output: @escaping NativeSpeechSink)
    async throws
  {
    try await engine.stream(request, directory: directory) { samples in
      try output(samples, VibeVoiceSpeechEngine.sampleRate)
    }
  }
}
