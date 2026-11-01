import FluidAudio
import Foundation
import SilliesTTS

actor KokoroTTSModel: NativeTTSModel {
  private static let sampleRate = 24_000
  private let manager: KokoroAneManager
  private var preparedVoice: SpeechVoice?

  init(configuration: TTSPreparation) async throws {
    guard let variant = KokoroAneVariant(rawValue: configuration.variant) else {
      throw TTSError.invalidRequest
    }
    try KokoroPackagePreparation.prepare(configuration)
    manager = KokoroAneManager(variant: variant, directory: configuration.directory, version: .v3)
    try await manager.initialize()
  }

  func synthesize(_ request: SpeechSynthesisRequest, output: @escaping NativeSpeechSink)
    async throws
  {
    let audio = try await manager.synthesizeDetailed(text: request.text, voice: request.voiceID)
    try output(audio.samples, Self.sampleRate)
  }

  func prepareVoice(_ voice: SpeechVoice) async throws {
    guard preparedVoice != voice else { return }
    try await manager.initialize(preloadVoices: [voice.id])
    preparedVoice = voice
  }
}
