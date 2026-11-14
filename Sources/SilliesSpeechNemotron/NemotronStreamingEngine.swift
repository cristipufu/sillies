import Foundation
import SilliesSpeech

/// One decoder per audio source. The shared speech channel bounds each utterance and owns cancellation.
actor NemotronStreamingEngine: ReusableSpeechEngine {
  nonisolated private let executor = SpeechWorkerExecutor()
  nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
  private var decoder: (any NemotronDecoding)?
  private var progress = SpeechIncrementalWindow()
  private var normalization = SpeechSignalNormalization()

  init() {}
  init(decoder: any NemotronDecoding, normalization: SpeechSignalNormalization = .init()) {
    self.decoder = decoder
    self.normalization = normalization
  }

  isolated deinit { dispatchPrecondition(condition: .notOnQueue(.main)) }

  func load(_ directory: URL, language: SpeechLanguage) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    decoder = try await NemotronNativeDecoder.load(directory, language: language)
  }

  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    guard let decoder else {
      throw SpeechError.unavailable(String(localized: "The speech model is not ready."))
    }
    do {
      let adjustment = try normalization.prepare(request.samples)
      let update = try progress.advance(request, inputGain: adjustment.gain)
      if update.action == .restart {
        try await decoder.reset()
      }
      let result = try await decoder.decode(
        adjustment.apply(to: update.samples), phase: update.phase)
      try Task.checkCancellation()
      return SpeechWindowResult(
        words: result.words.map {
          SpeechWord(
            text: $0.text, start: $0.start - update.windowOffset,
            end: $0.end - update.windowOffset, boundary: $0.boundary)
        }, detectedLanguage: result.detectedLanguage,
        timing: update.action == .append ? .continuous : .reestimated)
    } catch {
      resetProgress()
      throw error
    }
  }

  func resetForReuse() async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    defer { resetProgress() }
    try await decoder?.reset()
  }

  private func resetProgress() {
    progress.reset()
    normalization.reset()
  }
}
