import Foundation
import SilliesFishSpeech
import SilliesTTS

struct FishTTSModel: NativeTTSModel {
  private let engine = FishSpeechEngine()
  private let directory: URL

  init(configuration: TTSPreparation) throws {
    guard configuration.variant == "s2-pro-8bit" else { throw TTSError.invalidRequest }
    directory = configuration.directory
  }

  func synthesize(_ request: SpeechSynthesisRequest, output: @escaping NativeSpeechSink)
    async throws
  {
    try await engine.stream(request, directory: directory) { samples in
      try output(samples, FishConfiguration.sampleRate)
    }
  }
}
