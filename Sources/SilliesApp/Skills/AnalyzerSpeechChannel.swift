import AVFoundation
import Foundation
@preconcurrency import Speech

final class AnalyzerSpeechChannel: LocalSpeechChannel, @unchecked Sendable {
  private let analyzer: SpeechAnalyzer
  private let continuation: AsyncStream<AnalyzerInput>.Continuation
  private let converter: SpeechBufferConverter
  private let chunker: SpeechAudioChunker
  private let failure: LocalSpeechFactory.Failure
  private var resultsTask: Task<Void, Never>?

  private init(
    analyzer: SpeechAnalyzer, continuation: AsyncStream<AnalyzerInput>.Continuation,
    format: AVAudioFormat, failure: @escaping LocalSpeechFactory.Failure
  ) {
    self.analyzer = analyzer
    self.continuation = continuation
    converter = SpeechBufferConverter(format: format)
    chunker = SpeechAudioChunker(format: format)
    self.failure = failure
  }

  static func make(
    locale: Locale, output: @escaping LocalSpeechFactory.Output,
    failure: @escaping LocalSpeechFactory.Failure
  ) async throws -> AnalyzerSpeechChannel {
    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
      throw AudioCaptureFailure.unavailable(
        "This Apple speech model is not installed. Choose a language marked Ready on this Mac.")
    }
    try Task.checkCancellation()
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
    else {
      throw AudioCaptureFailure.unavailable(
        "The on-device speech model is not ready for this language.")
    }
    let analyzer = SpeechAnalyzer(
      modules: [transcriber], options: .init(priority: .utility, modelRetention: .whileInUse))
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(
      bufferingPolicy: .bufferingOldest(SpeechAudioChunker.streamCapacity))
    let channel = AnalyzerSpeechChannel(
      analyzer: analyzer, continuation: continuation, format: format, failure: failure)
    channel.resultsTask = Task.detached(priority: .utility) {
      do {
        for try await result in transcriber.results {
          output(
            SpeechPhrase(
              text: String(result.text.characters), isFinal: result.isFinal,
              startTime: result.range.start.seconds, duration: result.range.duration.seconds,
              finalizedThrough: result.resultsFinalizationTime.seconds))
        }
      } catch {
        if !Task.isCancelled {
          failure("Local transcription stopped: \(error.localizedDescription)")
        }
      }
    }
    do {
      try await analyzer.prepareToAnalyze(in: format)
      try await analyzer.start(inputSequence: stream)
      return channel
    } catch {
      channel.cancel()
      throw error
    }
  }

  func append(_ buffer: AVAudioPCMBuffer) {
    do {
      let converted = try converter.convert(buffer)
      guard converted.frameLength > 0 else { return }
      for chunk in try chunker.append(converted) { yield(chunk) }
    } catch { failure(error.localizedDescription) }
  }

  func finish(completion: @escaping @Sendable () -> Void) {
    if let remaining = chunker.flush() { yield(remaining) }
    continuation.finish()
    let analyzer = analyzer
    let results = resultsTask
    Task.detached(priority: .utility) {
      do { try await analyzer.finalizeAndFinishThroughEndOfInput() } catch {
        fputs("Speech finalization failed: \(error.localizedDescription)\n", stderr)
      }
      await results?.value
      completion()
    }
  }

  private func yield(_ buffer: AVAudioPCMBuffer) {
    if case .dropped = continuation.yield(AnalyzerInput(buffer: buffer)) {
      failure(
        "Speech processing couldn’t keep pace with the audio. Finish to save the available transcript."
      )
      fputs(
        "Speech input exceeded its \(SpeechAudioChunker.bufferedDuration)-second buffer.\n", stderr)
    }
  }

  func cancel() {
    continuation.finish()
    resultsTask?.cancel()
    let analyzer = analyzer
    Task.detached { await analyzer.cancelAndFinishNow() }
  }
}
