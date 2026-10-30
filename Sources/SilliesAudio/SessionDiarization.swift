import AVFoundation
import Foundation
import SilliesCore
import SilliesSpeech

/// Speaker state outlives recognizer/language changes and never stores the full meeting timeline.
final class SessionDiarization: Sendable {
  typealias Output = @Sendable (SpeechPhrase, SessionAudioSource) -> Void
  private static let maximumPendingPhrases = 64
  private static let maximumPendingCharacters = 16_384
  private final class Source {
    let channel: any LocalSpeechChannel
    var timeline = SpeakerActivityTimeline()
    var offset: TimeInterval?
    var pending: [SpeechPhrase] = []
    var pendingCharacters = 0
    var isStopped = false
    init(channel: any LocalSpeechChannel) { self.channel = channel }
  }
  private final class State {
    var sources: [SessionAudioSource: Source]
    init(channels: [SessionAudioSource: any LocalSpeechChannel]) {
      sources = channels.mapValues(Source.init)
    }
  }
  private let storage: SerialQueueStorage<State>
  private let channels: SpeechChannelGroup
  private let output: Output
  private let notice: @Sendable (String) -> Void

  init(
    channels: [SessionAudioSource: any LocalSpeechChannel], queue: DispatchQueue,
    output: @escaping Output, notice: @escaping @Sendable (String) -> Void
  ) {
    self.channels = SpeechChannelGroup(id: UUID(), channels: channels, queue: queue)
    self.output = output
    self.notice = notice
    storage = SerialQueueStorage(queue: queue) { State(channels: channels) }
  }

  func append(_ buffer: AVAudioPCMBuffer, source: SessionAudioSource, elapsed: TimeInterval) {
    storage.withValue { state in
      guard let stream = state.sources[source], !stream.isStopped else { return }
      if stream.offset == nil {
        stream.offset = max(0, elapsed - Double(buffer.frameLength) / buffer.format.sampleRate)
      }
      stream.channel.append(buffer)
    }
  }

  func receive(_ phrase: SpeechPhrase, source: SessionAudioSource) {
    storage.withValue { state in
      guard let stream = state.sources[source], !stream.isStopped else {
        output(phrase, source)
        return
      }
      guard phrase.isFinal, let start = phrase.startTime, let duration = phrase.duration,
        start + duration > stream.timeline.processedThrough
      else {
        emit(phrase, source: source, stream: stream)
        return
      }
      guard stream.pending.count < Self.maximumPendingPhrases,
        stream.pendingCharacters + phrase.text.count <= Self.maximumPendingCharacters
      else {
        fail(
          "Speaker detection fell behind. Transcription continues without speaker labels.",
          source: source)
        output(phrase, source)
        return
      }
      stream.pending.append(phrase)
      stream.pendingCharacters += phrase.text.count
      let preview = SpeechPhrase(
        text: phrase.text, isFinal: false,
        startTime: phrase.startTime, duration: phrase.duration)
      output(preview, source)
    }
  }

  func receive(_ batch: SpeakerActivityBatch, source: SessionAudioSource) {
    storage.withValue { state in
      guard let stream = state.sources[source], !stream.isStopped else { return }
      do {
        try stream.timeline.append(batch.shifted(by: stream.offset ?? 0))
        while let phrase = stream.pending.first,
          (phrase.startTime ?? 0) + (phrase.duration ?? 0) <= stream.timeline.processedThrough
        {
          stream.pending.removeFirst()
          stream.pendingCharacters -= phrase.text.count
          emit(phrase, source: source, stream: stream)
        }
      } catch {
        fputs("Speaker activity rejected: \(error)\n", stderr)
        fail(
          "Speaker detection stopped. Transcription continues without speaker labels.",
          source: source)
      }
    }
  }

  func flushPending() {
    storage.withValue { state in
      for (source, stream) in state.sources {
        for phrase in stream.pending { emit(phrase, source: source, stream: stream) }
        stream.pending.removeAll()
        stream.pendingCharacters = 0
      }
    }
  }

  func fail(_ message: String, source: SessionAudioSource) {
    storage.withValue { state in
      guard let stream = state.sources[source], !stream.isStopped else { return }
      stream.isStopped = true
      stream.channel.cancel()
      for phrase in stream.pending { emit(phrase, source: source, stream: stream) }
      stream.pending.removeAll()
      stream.pendingCharacters = 0
      notice(message)
    }
  }

  func finish(completion: @escaping @Sendable () -> Void) {
    channels.finish(reason: .sessionEnd) { [weak self] notice in
      if notice != nil {
        self?.notice(
          "Speaker detection took too long to finish. The available labels and transcript were preserved."
        )
      }
      self?.flushPending()
      completion()
    }
  }

  func cancel() {
    storage.withValue { state in
      for stream in state.sources.values {
        stream.isStopped = true
      }
    }
    channels.cancel()
    flushPending()
  }

  private func emit(_ phrase: SpeechPhrase, source: SessionAudioSource, stream: Source) {
    for attributed in SpeakerPhraseAttributor.annotate(phrase, using: stream.timeline) {
      output(attributed, source)
    }
  }
}
