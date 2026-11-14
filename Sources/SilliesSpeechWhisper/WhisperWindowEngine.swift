import Foundation
import SilliesSpeech
@preconcurrency import WhisperKit

actor WhisperWindowEngine: SpeechWindowEngine {
  nonisolated var finalizationPolicy: SpeechFinalizationPolicy { .reuseUnchangedDraft }
  nonisolated private let executor = SpeechWorkerExecutor()
  nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
  private var pipeline: WhisperKit?
  private var vocabulary = WhisperVocabularyPrompt()

  // Releasing large Core ML allocations must not inherit the UI caller's executor.
  isolated deinit { dispatchPrecondition(condition: .notOnQueue(.main)) }

  func load(_ directory: URL) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    let config = WhisperKitConfig(
      modelFolder: directory.path, tokenizerFolder: directory,
      computeOptions: ModelComputeOptions(melCompute: .cpuOnly),
      segmentSeeker: WhisperSegmentSeeker(context: .captured),
      verbose: false, logLevel: .error, prewarm: true, load: true, download: false)
    pipeline = try await OfflineWhisperKit(config)
    vocabulary = WhisperVocabularyPrompt()
    try Task.checkCancellation()
  }

  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    dispatchPrecondition(condition: .notOnQueue(.main))
    return try await decodeWindow(request).result
  }

  func decodeWindow(_ request: SpeechWindowRequest) async throws -> WhisperDecodingOutcome {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard let pipeline else {
      throw SpeechError.unavailable(String(localized: "Whisper is not ready."))
    }
    let options = decodingOptions(for: request, tokenizer: pipeline.tokenizer)
    let input = try WhisperTranscriptionInput(request.samples, options: options)
    pipeline.segmentSeeker = WhisperSegmentSeeker(context: input.context)
    let results =
      input.samples.isEmpty
      ? [] : try await pipeline.transcribe(audioArray: input.samples, decodeOptions: options)
    return .init(
      nativeResults: results, context: input.context, options: options)
  }

  private func decodingOptions(for request: SpeechWindowRequest, tokenizer: WhisperTokenizer?)
    -> DecodingOptions
  {
    var options = DecodingOptions()
    options.task = .transcribe
    options.language =
      request.language.isAutomatic ? nil : request.language.locale.language.languageCode?.identifier
    options.detectLanguage = request.language.isAutomatic
    options.wordTimestamps = true
    options.skipSpecialTokens = true
    options.temperatureFallbackCount = 1
    options.concurrentWorkerCount = 1
    if let tokenizer {
      options.promptTokens = vocabulary.tokens(for: request.context.vocabulary) {
        tokenizer.encode(text: $0)
      }
    }
    return options
  }
}
