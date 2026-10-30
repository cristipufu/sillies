import AVFoundation
import Foundation
import SilliesSpeech
@preconcurrency import Speech
import Synchronization

final class AnalyzerSpeechChannel: LocalSpeechChannel {
  private let analyzer: SpeechAnalyzer
  private let continuation: AsyncStream<AnalyzerInput>.Continuation
  // AVAudioConverter may retain its input; both converter and chunker stay inside input.withLock.
  private struct InputState: @unchecked Sendable {
    let converter: SpeechBufferConverter
    let chunker: SpeechAudioChunker
    var closed = false
  }
  private let input: Mutex<InputState>
  private let failure: LocalSpeechFactory.Failure
  private let resultsTask: Task<Void, Never>

  private init(
    analyzer: SpeechAnalyzer, continuation: AsyncStream<AnalyzerInput>.Continuation,
    format: AVAudioFormat, resultsTask: Task<Void, Never>,
    failure: @escaping LocalSpeechFactory.Failure
  ) {
    self.analyzer = analyzer
    self.continuation = continuation
    input = Mutex(
      InputState(
        converter: SpeechBufferConverter(format: format),
        chunker: SpeechAudioChunker(format: format)))
    self.resultsTask = resultsTask
    self.failure = failure
  }

  static func make(
    locale: Locale, output: @escaping LocalSpeechFactory.Output,
    failure: @escaping LocalSpeechFactory.Failure
  ) async throws -> AnalyzerSpeechChannel {
    let transcriber = SpeechTranscriber(
      locale: locale, preset: .timeIndexedProgressiveTranscription)
    guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
      throw SpeechError.unavailable(
        "This Apple speech model is not installed. Choose a language marked Ready on this Mac.")
    }
    try Task.checkCancellation()
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
    else {
      throw SpeechError.unavailable(
        "The on-device speech model is not ready for this language.")
    }
    let analyzer = SpeechAnalyzer(
      modules: [transcriber], options: .init(priority: .utility, modelRetention: .whileInUse))
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(
      bufferingPolicy: .bufferingOldest(SpeechAudioChunker.streamCapacity))
    let resultsTask = Task.detached(priority: .utility) {
      do {
        for try await result in transcriber.results {
          var phrase = SpeechPhrase(
            text: String(result.text.characters), isFinal: result.isFinal,
            startTime: result.range.start.seconds, duration: result.range.duration.seconds,
            finalizedThrough: result.resultsFinalizationTime.seconds)
          phrase.words = result.text.runs.compactMap { run in
            guard let range = run.audioTimeRange else { return nil }
            let text = String(result.text[run.range].characters)
            return SpeechWord(
              text: text.trimmingCharacters(in: .whitespacesAndNewlines),
              start: range.start.seconds, end: range.end.seconds,
              boundary: text.first?.isWhitespace == true ? .separated : .attached)
          }
          output(phrase)
        }
      } catch {
        if !Task.isCancelled {
          failure("Local transcription stopped: \(error.localizedDescription)")
        }
      }
    }
    let channel = AnalyzerSpeechChannel(
      analyzer: analyzer, continuation: continuation, format: format, resultsTask: resultsTask,
      failure: failure)
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
    let message: String? = input.withLock { input in
      guard !input.closed else { return nil }
      do {
        let converted = try input.converter.convert(buffer)
        guard converted.frameLength > 0 else { return nil }
        for chunk in try input.chunker.append(converted) {
          if let message = yield(chunk) { return message }
        }
        return nil
      } catch { return error.localizedDescription }
    }
    // Failure can synchronously cancel the channel; never invoke it under the input lock.
    if let message { failure(message) }
  }

  func finish(completion: @escaping @Sendable () -> Void) {
    let message: String? = input.withLock { input in
      guard !input.closed else { return nil }
      input.closed = true
      let message = input.chunker.flush().flatMap { yield($0) }
      continuation.finish()
      return message
    }
    if let message { failure(message) }
    let analyzer = analyzer
    let results = resultsTask
    Task.detached(priority: .utility) {
      do { try await analyzer.finalizeAndFinishThroughEndOfInput() } catch {
        fputs("Speech finalization failed: \(error.localizedDescription)\n", stderr)
      }
      await results.value
      completion()
    }
  }

  private func yield(_ buffer: AVAudioPCMBuffer) -> String? {
    if case .dropped = continuation.yield(AnalyzerInput(buffer: buffer)) {
      return
        "Speech processing couldn’t keep pace with the audio. Finish to save the available transcript."
    }
    return nil
  }

  func cancel() {
    input.withLock {
      $0.closed = true
      continuation.finish()
    }
    resultsTask.cancel()
    let analyzer = analyzer
    Task.detached { await analyzer.cancelAndFinishNow() }
  }
}
