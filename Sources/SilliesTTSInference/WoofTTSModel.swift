import Foundation
import SilliesModelStore
import SilliesTTS
import SilliesWoofSpeech

struct WoofTTSModel: NativeTTSModel {
  private let engine = WoofSpeechEngine()
  private let directory: URL

  init(configuration: TTSPreparation) throws {
    guard configuration.variant == "two-voices-int8" else { throw TTSError.invalidRequest }
    directory = configuration.directory
  }

  func prepareVoice(_ voice: SpeechVoice) async throws {
    do {
      try await engine.prepare(directory: directory, voiceID: voice.id)
    } catch is CancellationError { throw CancellationError() } catch let error as TTSError {
      throw error
    } catch { throw ModelStoreError.invalidArtifact("Woof") }
  }

  func synthesize(_ request: SpeechSynthesisRequest, output: @escaping NativeSpeechSink)
    async throws
  {
    try await engine.stream(request, directory: directory) { samples in
      try output(samples, WoofSpeechEngine.sampleRate)
    }
  }
}
