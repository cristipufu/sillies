import AVFoundation
import Foundation
import SilliesCore

/// Switches recognizers without restarting capture or the audio file. State lives on the capture queue.
final class SessionSpeechPipeline: Sendable {
  enum Event: Sendable {
    case textChanged
    case changingLanguage(SpeechLanguage)
    case languageChanged(SpeechLanguage)
    case failed(SessionFailure)
  }
  struct Configuration: Sendable {
    let sources: [SessionAudioSource]
    let queue: DispatchQueue
    var makeChannel: LocalSpeechFactory.Make = {
      try await LocalSpeechFactory.make(language: $0, output: $1, failure: $2)
    }
  }
  private struct BufferedAudio {
    let buffer: AVAudioPCMBuffer
    let source: SessionAudioSource
    let elapsed: TimeInterval
  }
  private static let maximumBufferedDuration = SpeechAudioChunker.bufferedDuration
  private static let maximumBufferedCallbacks = 2_048
  private let configuration: Configuration
  private let onEvent: @Sendable (Event) -> Void
  private final class State {
    var group: SpeechChannelGroup?
    var preparation: Task<Void, Never>?
    var generation = UUID()
    var startingCompletion: (@Sendable (Result<Void, Error>) -> Void)?
    enum Phase { case idle, preparing, running, switching, finishing, finished }
    var phase = Phase.idle
    var switching: Bool { phase == .switching }
    var stopped: Bool { phase == .finishing || phase == .finished }
    var buffered: [BufferedAudio] = []
    var bufferedDurations: [SessionAudioSource: TimeInterval] = [:]
    var sourceTimes: [SessionAudioSource: TimeInterval] = [:]
    var sourceOffsets: [SessionAudioSource: TimeInterval] = [:]
    var transcript = SpeechTranscript()
    var finalizationNotice: String?
    var switchTime: TimeInterval = 0

  }
  private let storage: SerialQueueStorage<State>

  init(configuration: Configuration, onEvent: @escaping @Sendable (Event) -> Void) {
    storage = SerialQueueStorage(queue: configuration.queue, makeValue: State.init)
    self.configuration = configuration
    self.onEvent = onEvent
  }

  var text: String {
    return storage.withValue { state in
      return state.transcript.text
    }
  }
  var preview: String {
    return storage.withValue { state in
      return state.transcript.preview
    }
  }

  func start(
    language: SpeechLanguage, completion: @escaping @Sendable (Result<Void, Error>) -> Void
  ) {
    storage.withValue { state in
      guard state.phase == .idle else {
        completion(.failure(CancellationError()))
        return
      }
      state.startingCompletion = completion
      prepare(language)
    }
  }

  func changeLanguage(_ language: SpeechLanguage, elapsed: TimeInterval) {
    storage.withValue { state in
      guard state.phase == .running, language.isInstalled else { return }
      state.phase = .switching
      state.switchTime = elapsed
      onEvent(.changingLanguage(language))
      guard let group = state.group else {
        prepare(language)
        return
      }
      group.finish(reason: .languageChange) { [weak self] notice in
        self?.completeLanguageDrain(notice, language: language)
      }
    }
  }

  func append(_ buffer: AVAudioPCMBuffer, source: SessionAudioSource, elapsed: TimeInterval) {
    storage.withValue { state in
      guard state.phase == .running || state.switching else { return }
      if state.switching {
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        guard state.buffered.count < Self.maximumBufferedCallbacks,
          state.bufferedDurations[source, default: 0] + duration <= Self.maximumBufferedDuration
        else {
          fail(
            SessionFailure(
              category: .transcription,
              message:
                "Changing language took too long. Finish to save the available transcript and audio."
            ))
          return
        }
        state.buffered.append(BufferedAudio(buffer: buffer, source: source, elapsed: elapsed))
        state.bufferedDurations[source, default: 0] += duration
      } else {
        if state.sourceOffsets[source] == nil {
          state.sourceOffsets[source] = max(
            0, elapsed - Double(buffer.frameLength) / buffer.format.sampleRate)
        }
        state.sourceTimes[source] = elapsed
        state.group?.append(buffer, source: source)
      }
    }
  }

  func finish(completion: @escaping @Sendable (String?) -> Void) {
    storage.withValue { state in
      if state.phase == .finished {
        completion(state.finalizationNotice)
        return
      }
      stopPreparing()
      guard let group = state.group else {
        state.phase = .finished
        completion(state.finalizationNotice)
        return
      }
      group.finish(reason: .sessionEnd) { [weak self] notice in
        guard let self else {
          completion(notice)
          return
        }
        self.completeSessionDrain(notice, completion: completion)
      }
    }
  }

  func cancel() {
    storage.withValue { state in
      stopPreparing()
      state.group?.cancel()
      state.transcript.preserveDrafts()
      state.group = nil
      state.phase = .finished
    }
  }

  private func stopPreparing() {
    storage.withValue { state in
      state.phase = .finishing
      state.generation = UUID()
      state.preparation?.cancel()
      state.preparation = nil
      if !state.buffered.isEmpty {
        state.finalizationNotice =
          "The session ended while language was changing. Earlier text was preserved; speech during the change may be missing from the transcript."
      }
      state.buffered.removeAll()
      state.bufferedDurations.removeAll()
      state.startingCompletion?(.failure(CancellationError()))
      state.startingCompletion = nil
    }
  }

  private func completeLanguageDrain(_ notice: String?, language: SpeechLanguage) {
    storage.withValue { state in
      guard !state.stopped else { return }
      state.finalizationNotice = notice ?? state.finalizationNotice
      state.transcript.preserveDrafts()
      state.group = nil
      prepare(language)
    }
  }

  private func completeSessionDrain(
    _ notice: String?, completion: @escaping @Sendable (String?) -> Void
  ) {
    storage.withValue { state in
      state.transcript.preserveDrafts()
      state.group = nil
      state.phase = .finished
      completion(notice ?? state.finalizationNotice)
    }
  }

  private func receiveFailure(_ message: String, groupID: UUID) {
    storage.withValue { state in
      guard state.group?.id == groupID else { return }
      fail(SessionFailure(category: .transcription, message: message))
    }
  }

  private func acceptPrepared(
    _ channels: [SessionAudioSource: any LocalSpeechChannel], language: SpeechLanguage, id: UUID
  ) {
    storage.withValue { state in
      guard !state.stopped, state.generation == id else {
        for channel in channels.values { channel.cancel() }
        return
      }
      install(channels, language: language, id: id)
    }
  }

  private func preparationFailed(_ error: Error, id: UUID) {
    storage.withValue { state in
      guard !state.stopped, state.generation == id else { return }
      state.preparation = nil
      let completion = state.startingCompletion
      state.startingCompletion = nil
      completion?(.failure(error))
      fail(SessionFailure(error, category: .transcription))
    }
  }

  private func prepare(_ language: SpeechLanguage) {
    let id = UUID()
    storage.withValue { state in
      state.generation = id
      if !state.switching { state.phase = .preparing }
    }
    let configuration = configuration
    let task = Task.detached(priority: .utility) { [weak self] in
      var channels: [SessionAudioSource: any LocalSpeechChannel] = [:]
      do {
        for source in configuration.sources {
          try Task.checkCancellation()
          channels[source] = try await configuration.makeChannel(
            language,
            { [weak self] phrase in
              configuration.queue.async { [weak self] in
                self?.receive(phrase, source: source, groupID: id)
              }
            },
            { [weak self] message in
              configuration.queue.async { [weak self] in self?.receiveFailure(message, groupID: id)
              }
            })
        }
        try Task.checkCancellation()
        let prepared = channels
        configuration.queue.async { [weak self] in
          guard let self else {
            for channel in prepared.values { channel.cancel() }
            return
          }
          self.acceptPrepared(prepared, language: language, id: id)
        }
      } catch {
        for channel in channels.values { channel.cancel() }
        configuration.queue.async { [weak self] in self?.preparationFailed(error, id: id) }
      }
    }
    storage.withValue { state in
      if state.stopped || state.generation != id { task.cancel() } else { state.preparation = task }
    }
  }

  private func install(
    _ channels: [SessionAudioSource: any LocalSpeechChannel], language: SpeechLanguage, id: UUID
  ) {
    storage.withValue { state in
      state.preparation = nil
      state.group = SpeechChannelGroup(id: id, channels: channels, queue: configuration.queue)
      state.sourceOffsets.removeAll()
      if state.switching { state.transcript.markLanguage(language.name, elapsed: state.switchTime) }
      state.phase = .running
      onEvent(.languageChanged(language))
      let pending = state.buffered
      state.buffered.removeAll(keepingCapacity: true)
      state.bufferedDurations.removeAll()
      for audio in pending { append(audio.buffer, source: audio.source, elapsed: audio.elapsed) }
      state.startingCompletion?(.success(()))
      state.startingCompletion = nil
      onEvent(.textChanged)
    }
  }

  private func receive(_ phrase: SpeechPhrase, source: SessionAudioSource, groupID: UUID) {
    storage.withValue { state in
      guard state.group?.id == groupID else { return }
      state.transcript.receive(
        phrase.shifted(by: state.sourceOffsets[source, default: state.switchTime]),
        source: source, elapsed: state.sourceTimes[source, default: 0])
      onEvent(.textChanged)
    }
  }

  private func fail(_ failure: SessionFailure) {
    storage.withValue { state in
      guard !state.stopped else { return }
      cancel()
      onEvent(.failed(failure))
    }
  }
}
