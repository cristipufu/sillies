import Foundation
import SilliesSpeech
@preconcurrency import WhisperKit

actor WhisperWindowEngine: SpeechWindowEngine {
  nonisolated private let executor = SpeechWorkerExecutor()
  nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
  private var pipeline: WhisperKit?

  // Releasing large Core ML allocations must not inherit the UI caller's executor.
  isolated deinit { dispatchPrecondition(condition: .notOnQueue(.main)) }

  func load(_ directory: URL) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    let config = WhisperKitConfig(
      modelFolder: directory.path, tokenizerFolder: directory,
      computeOptions: ModelComputeOptions(melCompute: .cpuOnly),
      verbose: false, logLevel: .error, prewarm: true, load: true, download: false)
    pipeline = try await OfflineWhisperKit(config)
    try Task.checkCancellation()
  }

  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard let pipeline else { throw SpeechError.unavailable("Whisper is not ready.") }
    var options = DecodingOptions()
    options.task = .transcribe
    options.language =
      request.language.isAutomatic ? nil : request.language.locale.language.languageCode?.identifier
    options.detectLanguage = request.language.isAutomatic
    options.wordTimestamps = true
    options.skipSpecialTokens = true
    options.temperatureFallbackCount = 1
    options.concurrentWorkerCount = 1
    let results = try await pipeline.transcribe(audioArray: request.samples, decodeOptions: options)
    return SpeechWindowResult(
      words: results.flatMap(\.segments).flatMap { segment in
        (segment.words ?? []).map {
          SpeechWord(
            text: $0.word.trimmingCharacters(in: .whitespaces), start: Double($0.start),
            end: Double($0.end),
            boundary: $0.word.first?.isWhitespace == true ? .separated : .attached)
        }
      }, detectedLanguage: results.first?.language)
  }
}
