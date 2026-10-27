import AVFoundation
import Foundation

/// Switches recognizers without restarting capture or the audio file. State lives on the capture queue.
final class SessionSpeechPipeline: @unchecked Sendable {
  enum Event: Sendable {
    case textChanged
    case changingLanguage(SpeechLanguage)
    case languageChanged(SpeechLanguage)
    case failed(String)
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
  private var group: SpeechChannelGroup?
  private var preparation: Task<Void, Never>?
  private var generation = UUID()
  private var startingCompletion: (@Sendable (Result<Void, Error>) -> Void)?
  private var switching = false
  private var stopped = false
  private var buffered: [BufferedAudio] = []
  private var bufferedDurations: [SessionAudioSource: TimeInterval] = [:]
  private var sourceTimes: [SessionAudioSource: TimeInterval] = [:]
  private var sourceOffsets: [SessionAudioSource: TimeInterval] = [:]
  private var transcript = SpeechTranscript()
  private var finalizationNotice: String?
  private var switchTime: TimeInterval = 0

  init(configuration: Configuration, onEvent: @escaping @Sendable (Event) -> Void) {
    self.configuration = configuration
    self.onEvent = onEvent
  }

  var text: String { transcript.text }

  func start(
    language: SpeechLanguage, completion: @escaping @Sendable (Result<Void, Error>) -> Void
  ) {
    startingCompletion = completion
    prepare(language)
  }

  func changeLanguage(_ language: SpeechLanguage, elapsed: TimeInterval) {
    guard !stopped, !switching, preparation == nil, language.isInstalled else { return }
    switching = true
    switchTime = elapsed
    onEvent(.changingLanguage(language))
    guard let group else {
      prepare(language)
      return
    }
    group.finish(reason: .languageChange) { [weak self] notice in
      guard let self, !self.stopped else { return }
      self.finalizationNotice = notice ?? self.finalizationNotice
      self.transcript.preserveDrafts()
      self.group = nil
      self.prepare(language)
    }
  }

  func append(_ buffer: AVAudioPCMBuffer, source: SessionAudioSource, elapsed: TimeInterval) {
    guard !stopped else { return }
    if switching {
      let duration = Double(buffer.frameLength) / buffer.format.sampleRate
      guard buffered.count < Self.maximumBufferedCallbacks,
        bufferedDurations[source, default: 0] + duration <= Self.maximumBufferedDuration
      else {
        fail("Changing language took too long. Finish to save the available transcript and audio.")
        return
      }
      buffered.append(BufferedAudio(buffer: buffer, source: source, elapsed: elapsed))
      bufferedDurations[source, default: 0] += duration
    } else {
      if sourceOffsets[source] == nil {
        sourceOffsets[source] = max(
          0, elapsed - Double(buffer.frameLength) / buffer.format.sampleRate)
      }
      sourceTimes[source] = elapsed
      group?.channels[source]?.append(buffer)
    }
  }

  func finish(completion: @escaping (String?) -> Void) {
    stopPreparing()
    guard let group else {
      completion(finalizationNotice)
      return
    }
    group.finish(reason: .sessionEnd) { [weak self] notice in
      guard let self else {
        completion(notice)
        return
      }
      self.transcript.preserveDrafts()
      self.group = nil
      completion(notice ?? self.finalizationNotice)
    }
  }

  func cancel() {
    stopPreparing()
    group?.cancel()
    transcript.preserveDrafts()
    group = nil
  }

  private func stopPreparing() {
    stopped = true
    generation = UUID()
    preparation?.cancel()
    preparation = nil
    if !buffered.isEmpty {
      finalizationNotice =
        "The session ended while language was changing. Earlier text was preserved; speech during the change may be missing from the transcript."
    }
    buffered.removeAll()
    bufferedDurations.removeAll()
    startingCompletion?(.failure(CancellationError()))
    startingCompletion = nil
  }

  private func prepare(_ language: SpeechLanguage) {
    let id = UUID()
    generation = id
    let configuration = configuration
    preparation = Task.detached(priority: .utility) { [weak self] in
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
              configuration.queue.async { [weak self] in
                guard self?.group?.id == id else { return }
                self?.fail(message)
              }
            })
        }
        try Task.checkCancellation()
        let prepared = channels
        configuration.queue.async { [weak self] in
          guard let self, !self.stopped, self.generation == id else {
            for channel in prepared.values { channel.cancel() }
            return
          }
          self.install(prepared, language: language, id: id)
        }
      } catch {
        for channel in channels.values { channel.cancel() }
        configuration.queue.async { [weak self] in
          guard let self, !self.stopped, self.generation == id else { return }
          self.preparation = nil
          self.startingCompletion?(.failure(error))
          self.startingCompletion = nil
          self.fail(error.localizedDescription)
        }
      }
    }
  }

  private func install(
    _ channels: [SessionAudioSource: any LocalSpeechChannel], language: SpeechLanguage, id: UUID
  ) {
    preparation = nil
    group = SpeechChannelGroup(id: id, channels: channels, queue: configuration.queue)
    sourceOffsets.removeAll()
    if switching { transcript.markLanguage(language.name, elapsed: switchTime) }
    switching = false
    onEvent(.languageChanged(language))
    let pending = buffered
    buffered.removeAll(keepingCapacity: true)
    bufferedDurations.removeAll()
    for audio in pending { append(audio.buffer, source: audio.source, elapsed: audio.elapsed) }
    startingCompletion?(.success(()))
    startingCompletion = nil
    onEvent(.textChanged)
  }

  private func receive(_ phrase: SpeechPhrase, source: SessionAudioSource, groupID: UUID) {
    guard group?.id == groupID else { return }
    transcript.receive(
      phrase.shifted(by: sourceOffsets[source, default: switchTime]),
      source: source, elapsed: sourceTimes[source, default: 0])
    onEvent(.textChanged)
  }

  private func fail(_ message: String) {
    guard !stopped else { return }
    cancel()
    onEvent(.failed(message))
  }
}
