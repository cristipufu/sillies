import AVFoundation
import Foundation
import SilliesCore
import SilliesSpeech

/// One recognizer reservation per utterance; microphone monitoring does not hold model priority.
final class ConversationSpeechTurn: Sendable {
  struct Configuration {
    let dictionary: PersonalDictionary
    let finalizationTimeout: TimeInterval
  }
  private static let maximumPreparationAudio: TimeInterval = 2
  private final class State {
    var channel: (any LocalSpeechChannel)?
    var preparation: Task<Void, Never>?
    var buffered: [AVAudioPCMBuffer] = []
    var duration: TimeInterval = 0
    var transcript = SpeechTranscript()
    var failure: SessionFailure?
    var finishing = false
    var result: AudioCaptureResult?
    var waiters: [@Sendable (AudioCaptureResult) -> Void] = []
    var deadline: DispatchWorkItem?
    var finalizationOwner: ConversationSpeechTurn?
  }
  private let queue: DispatchQueue
  private let storage: SerialQueueStorage<State>
  private let changed: @Sendable (String) -> Void
  private let failed: @Sendable (SessionFailure) -> Void
  private let finalizationTimeout: TimeInterval
  private let dictionary: PersonalDictionary

  init(
    queue: DispatchQueue, configuration: Configuration,
    changed: @escaping @Sendable (String) -> Void,
    failed: @escaping @Sendable (SessionFailure) -> Void
  ) {
    self.queue = queue
    storage = SerialQueueStorage(queue: queue, makeValue: State.init)
    self.changed = changed
    self.failed = failed
    dictionary = configuration.dictionary
    finalizationTimeout = configuration.finalizationTimeout
  }

  func prepare(
    language: SpeechLanguage, make: @escaping LocalSpeechFactory.Make,
    ready: @escaping @Sendable () -> Void = {}
  ) {
    storage.withValue { state in
      state.preparation = Task { [weak self, queue] in
        do {
          let channel = try await make(
            language,
            { [weak self] phrase in
              queue.async { [weak self] in self?.receive(phrase) }
            },
            { [weak self] message in
              queue.async { [weak self] in
                self?.fail(.init(category: .transcription, message: message))
              }
            })
          guard !Task.isCancelled else {
            channel.cancel()
            return
          }
          queue.async { [weak self] in
            guard let self else {
              channel.cancel()
              return
            }
            self.install(channel, ready: ready)
          }
        } catch {
          guard !Task.isCancelled else { return }
          queue.async { [weak self] in self?.fail(SessionFailure(error, category: .transcription)) }
        }
      }
    }
  }

  func append(_ buffer: AVAudioPCMBuffer) {
    storage.withValue { state in
      guard !state.finishing, state.result == nil else { return }
      state.duration += Double(buffer.frameLength) / buffer.format.sampleRate
      if let channel = state.channel {
        channel.append(buffer)
      } else if state.duration <= Self.maximumPreparationAudio {
        state.buffered.append(buffer)
      } else {
        fail(
          .init(
            category: .transcription,
            message: String(
              localized: "Speech recognition took too long to get ready. Please try speaking again."
            )))
      }
    }
  }

  func finish(_ completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    storage.withValue { state in
      if let result = state.result {
        completion(result)
        return
      }
      state.waiters.append(completion)
      guard !state.finishing else { return }
      state.finishing = true
      state.finalizationOwner = self
      let deadline = DispatchWorkItem { [weak self] in
        self?.fail(
          .init(
            category: .finalization,
            message: String(
              localized: "Speech finalization timed out. Your available words are kept.")))
      }
      state.deadline = deadline
      queue.asyncAfter(deadline: .now() + finalizationTimeout, execute: deadline)
      if let channel = state.channel { drain(channel) }
    }
  }

  private func install(_ channel: any LocalSpeechChannel, ready: @escaping @Sendable () -> Void) {
    storage.withValue { state in
      guard state.result == nil else {
        channel.cancel()
        return
      }
      state.preparation = nil
      state.channel = channel
      for buffer in state.buffered { channel.append(buffer) }
      state.buffered.removeAll()
      ready()
      if state.finishing { drain(channel) }
    }
  }
  private func drain(_ channel: any LocalSpeechChannel) {
    channel.finish { [weak self, queue] in queue.async { [weak self] in self?.complete() } }
  }
  private func receive(_ phrase: SpeechPhrase) {
    storage.withValue { state in
      guard state.result == nil else { return }
      state.transcript.receive(phrase, source: .microphone, elapsed: state.duration)
      changed(dictionary.replacing(in: state.transcript.preview))
    }
  }
  private func fail(_ failure: SessionFailure) {
    storage.withValue { state in
      guard state.result == nil else { return }
      state.failure = failure
      complete()
      failed(failure)
    }
  }
  private func complete() {
    storage.withValue { state in
      guard state.result == nil else { return }
      state.transcript.preserveDrafts()
      var result = AudioCaptureResult(
        transcript: dictionary.replacing(in: state.transcript.text), recordingURL: nil,
        duration: state.duration, failure: state.failure)
      result.segments = state.transcript.segments.map { segment in
        TranscriptSegment(
          sequence: segment.sequence, source: segment.source,
          start: segment.start, end: segment.end,
          text: dictionary.replacing(in: segment.text), speaker: segment.speaker)
      }
      state.result = result
      state.channel?.cancel()
      state.channel = nil
      state.preparation?.cancel()
      state.preparation = nil
      state.deadline?.cancel()
      state.deadline = nil
      state.buffered.removeAll()
      let waiters = state.waiters
      state.waiters.removeAll()
      for waiter in waiters { waiter(result) }
      state.finalizationOwner = nil
    }
  }
}
