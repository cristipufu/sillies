import FluidAudio
import Foundation
import SilliesSpeech

actor ParakeetWindowEngine: SpeechWindowEngine {
  nonisolated private let executor = SpeechWorkerExecutor()
  nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
  private let manager = AsrManager(config: .default)

  isolated deinit { dispatchPrecondition(condition: .notOnQueue(.main)) }

  func load(_ directory: URL) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    let models = try AsrModels.loadLocal(from: directory, version: .ultra)
    try await manager.loadModels(models)
    try Task.checkCancellation()
  }

  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    dispatchPrecondition(condition: .notOnQueue(.main))
    var decoder = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
    let result = try await manager.transcribe(request.samples, decoderState: &decoder)
    return SpeechWindowResult(
      words: buildWordTimings(from: result.tokenTimings ?? []).map {
        SpeechWord(text: $0.word, start: $0.startTime, end: $0.endTime)
      })
  }
}
