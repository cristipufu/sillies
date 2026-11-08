import CoreML
import FluidAudio
import Foundation
import SilliesSpeech

actor ParakeetWindowEngine: SpeechWindowEngine {
  // Keep this encoder off the ANE and MPSGraph specialization paths. CPU inference
  // leaves the GPU available for the interface and starts without accelerator compilation.
  private static let encoderComputeUnits: MLComputeUnits = .cpuOnly
  nonisolated var finalizationPolicy: SpeechFinalizationPolicy { .reuseUnchangedDraft }
  nonisolated private let executor = SpeechWorkerExecutor()
  nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
  private let manager = AsrManager(config: .default)

  isolated deinit { dispatchPrecondition(condition: .notOnQueue(.main)) }

  func load(_ directory: URL) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    let models = try AsrModels.loadLocal(
      from: directory, version: .ultra, encoderComputeUnits: Self.encoderComputeUnits)
    try await manager.loadModels(models)
    try Task.checkCancellation()
  }

  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard !request.samples.isEmpty else { return SpeechWindowResult(words: []) }
    let input = try ParakeetTranscriptionInput(request)
    var decoder = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
    let result = try await manager.transcribe(
      input.samples, decoderState: &decoder, language: input.language)
    return SpeechWindowResult(
      words: buildWordTimings(from: result.tokenTimings ?? []).map {
        SpeechWord(text: $0.word, start: $0.startTime, end: $0.endTime)
      })
  }
}
