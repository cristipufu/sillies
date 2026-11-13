import AVFoundation
import Foundation
import SilliesCore
import SilliesSpeech

/// Commands enter one capture worker; synchronous buffer processing stays off the main actor.
package final class AudioTranscriptionService: SessionAudioCapture {
  private static let publicationInterval: TimeInterval = 0.5
  private let configuration: AudioCaptureConfiguration
  private let onUpdate: @Sendable (AudioCaptureUpdate) -> Void
  private let dependencies: AudioCaptureDependencies
  private let queue: DispatchQueue
  private let inputQueue: AudioCaptureInputQueue
  private let preparation = CapturePreparation()
  private let storage: SerialQueueStorage<AudioCaptureState>

  package convenience init(
    configuration: AudioCaptureConfiguration, speech: @escaping LocalSpeechFactory.Make,
    diarization: SpeakerDiarizationFactory.Make? = nil,
    events: AudioCaptureEvents
  ) {
    self.init(
      configuration: configuration,
      dependencies: .init(
        reportOverload: events.reportOverload, lifecycle: events.lifecycle,
        speech: speech, diarization: diarization),
      onUpdate: events.update)
  }

  init(
    configuration: AudioCaptureConfiguration, dependencies: AudioCaptureDependencies,
    onUpdate: @escaping @Sendable (AudioCaptureUpdate) -> Void
  ) {
    let queue = dependencies.queue
    self.queue = queue
    inputQueue = AudioCaptureInputQueue(queue: queue)
    storage = SerialQueueStorage(queue: queue, makeValue: AudioCaptureState.init)
    self.configuration = configuration
    self.dependencies = dependencies
    self.onUpdate = onUpdate
  }

  package func start() {
    queue.async { [self] in
      guard storage.withValue({ $0.lifecycle.beginPreparation() }) else { return }
      preparation.launch { [weak self, configuration] in
        do {
          try Task.checkCancellation()
          self?.onUpdate(.preparing(String(localized: "Preparing on-device speech…")))
          guard let sources = try await self?.prepareSources() else { return }
          try await self?.prepareSpeech()
          let label = try await Self.startSources(sources, appName: configuration.target?.appName)
          self?.captureStarted(label)
        } catch is CancellationError {
          // Finishing during preparation cancels startup normally.
        } catch { self?.reportFailure(SessionFailure(error, category: .captureUnavailable)) }
      }
    }
  }

  private struct CaptureSources: Sendable {
    let application: (any ApplicationCapture)?
    let microphone: (any MicrophoneCapture)?
  }

  private static func startSources(_ sources: CaptureSources, appName: String?) async throws
    -> String
  {
    try Task.checkCancellation()
    if let application = sources.application { try await application.start() }
    try Task.checkCancellation()
    let microphoneName = try await sources.microphone?.start()
    try Task.checkCancellation()
    return [appName, microphoneName].compactMap { $0 }.joined(separator: " + ")
  }

  private func captureStarted(_ label: String) {
    queue.async { [self] in
      let now = dependencies.now()
      guard
        storage.withValue({ state in
          guard state.lifecycle.beginCapture(at: now) else { return false }
          state.speakerObservationBoundary = now
          return true
        })
      else { return }
      dependencies.lifecycle(.capturing)
      onUpdate(.capturing(label))
    }
  }

  private func prepareSources() async throws -> CaptureSources {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          let sources = try storage.withValue { state in
            guard state.lifecycle.phase == .preparing else { throw CancellationError() }
            if let url = configuration.recordingURL {
              state.writer = try AudioRecordingWriter(destination: url)
            }
            if configuration.kind.isMeetingSession {
              state.meetingAudio = try MeetingAudioProcessor()
            }
            if configuration.sources.contains(.microphone) {
              state.microphone = dependencies.microphone(
                { [weak self] in self?.enqueue($0) }, { [weak self] in self?.reportFailure($0) })
            }
            if configuration.sources.contains(.application) {
              guard let target = configuration.target else {
                throw AudioCaptureFailure.unavailable(
                  String(localized: "Choose a meeting window first."))
              }
              state.application = dependencies.application(
                target, { [weak self] in self?.enqueue($0) },
                { [weak self] in self?.reportFailure($0) })
            }
            return CaptureSources(application: state.application, microphone: state.microphone)
          }
          continuation.resume(returning: sources)
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  private func prepareSpeech() async throws {
    guard let language = configuration.language else {
      throw AudioCaptureFailure.unavailable(
        String(localized: "Choose a transcription language before starting."))
    }
    let speakerChannels = try await prepareSpeakerChannels()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async { [self] in
        storage.withValue { state in
          guard state.lifecycle.phase == .preparing else {
            for channel in speakerChannels.values { channel.cancel() }
            continuation.resume(throwing: CancellationError())
            return
          }
          let pipeline = SessionSpeechPipeline(
            configuration: .init(
              sources: configuration.sources, queue: queue, makeChannel: dependencies.speech,
              dictionary: configuration.dictionary),
            speakerChannels: speakerChannels
          ) { [weak self] in self?.speechChanged($0) }
          state.speech = pipeline
          pipeline.start(language: language) { continuation.resume(with: $0) }
        }
      }
    }
  }

  private func prepareSpeakerChannels() async throws -> [SessionAudioSource: any LocalSpeechChannel]
  {
    guard let make = dependencies.diarization else { return [:] }
    var channels: [SessionAudioSource: any LocalSpeechChannel] = [:]
    do {
      for source in configuration.sources {
        try Task.checkCancellation()
        channels[source] = try await make(
          .init(
            output: { [weak self, queue] batch in
              queue.async { [weak self] in
                self?.storage.withValue { $0.speech?.receiveSpeakerActivity(batch, source: source) }
              }
            },
            failure: { [weak self, queue] message in
              queue.async { [weak self] in
                self?.storage.withValue {
                  $0.speech?.speakerDetectionFailed(message, source: source)
                }
              }
            }))
      }
      try Task.checkCancellation()
      return channels
    } catch {
      for channel in channels.values { channel.cancel() }
      if Task.isCancelled { throw CancellationError() }
      fputs("Speaker detection preparation failed: \(error.localizedDescription)\n", stderr)
      let message =
        String(
          localized:
            "Speaker detection unavailable. Transcription continues. \(error.localizedDescription)")
      queue.async { [weak self] in self?.speakerDetectionStopped(message) }
      return [:]
    }
  }

  private func speechChanged(_ event: SessionSpeechPipeline.Event) {
    storage.withValue { state in
      guard state.lifecycle.phase != .finished else { return }
      switch event {
      case .textChanged: publish(level: 0)
      case .changingLanguage(let language): onUpdate(.changingLanguage(language))
      case .languageChanged(let language): onUpdate(.languageChanged(language))
      case .speakerNotice(let message): speakerDetectionStopped(message)
      case .recovery(let update): onUpdate(.transcriptionRecovery(update))
      case .failed(let failure):
        if state.lifecycle.phase == .preparing {
          fail(failure)
        } else {
          state.transcriptionFailure = failure
          onUpdate(.transcriptionStopped(failure))
        }
      }
    }
  }

  private func speakerDetectionStopped(_ message: String) {
    storage.withValue { state in
      guard state.lifecycle.phase != .finished else { return }
      state.speakerDetectionNotice = message
      onUpdate(.speakerDetectionNotice(message))
    }
  }

  package func changeLanguage(_ language: SpeechLanguage) {
    queue.async { [self] in
      storage.withValue { state in
        guard state.lifecycle.canChangeLanguage else { return }
        state.speech?.changeLanguage(
          language, elapsed: state.lifecycle.elapsed(at: dependencies.now()))
      }
    }
  }

  package func observeCallSpeakers(_ observation: CallSpeakerObservation) {
    queue.async { [self] in
      storage.withValue { state in
        let now = dependencies.now()
        guard state.lifecycle.acceptsAudio, configuration.kind.isMeetingSession,
          let target = configuration.target,
          observation.source == .init(processID: target.processID, windowID: target.windowID),
          observation.capturedAt.isFinite,
          observation.capturedAt >= state.speakerObservationBoundary,
          observation.capturedAt <= now,
          now - observation.capturedAt <= CallSpeakerTimeline.maximumHold
        else { return }
        state.speech?.observeCallSpeakers(
          observation, at: state.lifecycle.sampleElapsed(at: observation.capturedAt))
      }
    }
  }

  package func pause() {
    queue.async { [self] in
      storage.withValue { state in
        guard state.lifecycle.acceptsAudio else { return }
        do {
          try flushMeetingAudio(state)
          try state.meetingAudio?.reset()
          let now = dependencies.now()
          state.lifecycle.pause(at: now)
          state.speakerObservationBoundary = now
          invalidateCallSpeakers(state, at: now)
        } catch { fail(SessionFailure(error, category: .audioProcessing)) }
      }
    }
  }

  package func resume() {
    queue.async { [self] in
      storage.withValue { state in
        let now = dependencies.now()
        if state.lifecycle.resume(at: now) { state.speakerObservationBoundary = now }
      }
    }
  }

  private func invalidateCallSpeakers(_ state: AudioCaptureState, at now: TimeInterval) {
    guard let target = configuration.target else { return }
    let reading = CallSpeakerObservation(
      source: .init(processID: target.processID, windowID: target.windowID),
      capturedAt: now, availability: .unavailable)
    state.speech?.observeCallSpeakers(reading, at: state.lifecycle.elapsed(at: now))
  }

  package func refreshProgress() {
    queue.async { [self] in
      guard storage.withValue({ $0.lifecycle.canChangeLanguage }) else { return }
      publish(level: 0)
    }
  }

  private func enqueue(_ packet: AudioCaptureInputQueue.Packet) {
    inputQueue.enqueue(
      packet, receive: { [weak self] in self?.process($0) },
      overflow: { [weak self] in self?.captureOverloaded() })
  }

  private func captureOverloaded() {
    if let backlog = inputQueue.overload { dependencies.reportOverload(backlog) }
    fail(
      SessionFailure(
        category: .audioProcessing,
        message: String(
          localized:
            "Audio capture fell behind. Finish to save the available transcript and recording.")))
  }

  private func process(_ packet: AudioCaptureInputQueue.Packet) {
    storage.withValue { state in
      guard state.lifecycle.acceptsAudio, let buffer = AudioPCMTools.buffer(from: packet.sample)
      else { return }
      do {
        if let meetingAudio = state.meetingAudio {
          try meetingAudio.append(buffer, source: packet.source, at: packet.sampleStartTime)
          while let output = try meetingAudio.nextReadyOutput() {
            try consume(output, state: state)
          }
        } else {
          try state.writer?.append(buffer)
          state.speech?.append(
            buffer, source: packet.source,
            elapsed: state.lifecycle.sampleElapsed(at: packet.capturedAt))
        }
        publish(level: AudioPCMTools.level(buffer))
      } catch { fail(SessionFailure(error, category: .audioProcessing)) }
    }
  }

  private func consume(_ output: MeetingAudioProcessor.Output, state: AudioCaptureState) throws {
    let elapsed = state.lifecycle.sampleElapsed(at: output.endTime)
    try state.writer?.append(output.recording)
    state.speech?.append(output.meeting, source: .application, elapsed: elapsed)
    state.speech?.append(output.microphone, source: .microphone, elapsed: elapsed)
  }

  private func flushMeetingAudio(_ state: AudioCaptureState) throws {
    while let output = try state.meetingAudio?.nextFinalOutput() {
      try consume(output, state: state)
    }
  }

  private func publish(level: Double) {
    storage.withValue { state in
      let now = dependencies.now()
      guard now - state.lastPublishedAt >= Self.publicationInterval else { return }
      state.lastPublishedAt = now
      onUpdate(
        .transcript(
          state.speech?.preview ?? "", level: level, elapsed: state.lifecycle.elapsed(at: now)))
    }
  }

  private func reportFailure(_ failure: SessionFailure) { queue.async { [self] in fail(failure) } }

  private func fail(_ failure: SessionFailure) {
    storage.withValue { state in
      guard state.lifecycle.fail(failure, at: dependencies.now()) else { return }
      preparation.cancel()
      inputQueue.stop()
      stopCaptureDevices(state)
      // Keep staged audio and recognition until the normal finish path drains both in order.
      onUpdate(.failed(failure))
      dependencies.lifecycle(.failed(failure))
      fputs("Audio session failed: \(failure.message)\n", stderr)
    }
  }

  package func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    finish(ending: .userFinished, completion: completion)
  }

  package func finish(
    ending reason: SessionEndReason, completion: @escaping @Sendable (AudioCaptureResult) -> Void
  ) {
    inputQueue.stop()
    preparation.cancel()
    queue.async { [self] in
      storage.withValue { state in
        if let result = state.result {
          completion(result)
          return
        }
        state.finishCompletions.append(completion)
        guard state.lifecycle.beginFinishing(at: dependencies.now(), reason: reason) else { return }
        dependencies.lifecycle(.finishing(reason))
        stopCaptureDevices(state)
        do { try flushMeetingAudio(state) } catch {
          let failure = SessionFailure(error, category: .finalization)
          state.lifecycle.recordFinalizationNotice(failure)
          dependencies.lifecycle(.failed(failure))
          fputs("Meeting audio finalization failed: \(error.localizedDescription)\n", stderr)
        }
        state.meetingAudio = nil
        state.finalizationOwner = self
        beginResourceDrain(state)
      }
    }
  }

  private func beginResourceDrain(_ state: AudioCaptureState) {
    stopCaptureDevices(state)
    if state.speech != nil { state.pendingStops.insert(.speech) }
    guard !state.pendingStops.isEmpty else {
      deliverFinish()
      return
    }
    state.speech?.finish { [weak self] notice in self?.resourceStopped(.speech, notice: notice) }
    let deadline = DispatchWorkItem { [weak self] in self?.finishTimedOut() }
    state.deadline = deadline
    queue.asyncAfter(
      deadline: .now() + dependencies.finalizationTimeout(for: configuration.kind),
      execute: deadline)
  }

  private func stopCaptureDevices(_ state: AudioCaptureState) {
    if let microphone = state.microphone, state.requestedStops.insert(.microphone).inserted {
      state.pendingStops.insert(.microphone)
      microphone.stop { [weak self] in self?.resourceStopped(.microphone) }
    }
    if let application = state.application, state.requestedStops.insert(.application).inserted {
      state.pendingStops.insert(.application)
      application.stop { [weak self] in self?.resourceStopped(.application) }
    }
  }

  private func resourceStopped(_ source: AudioCaptureState.StopSource, notice: String? = nil) {
    queue.async { [self] in
      storage.withValue { state in
        guard state.lifecycle.phase != .finished, state.pendingStops.remove(source) != nil else {
          return
        }
        dependencies.lifecycle(.resourceStopped(source))
        state.lifecycle.recordFinalizationNotice(
          notice.map { SessionFailure(category: .finalization, message: $0) })
        if state.lifecycle.phase == .finishing, state.pendingStops.isEmpty { deliverFinish() }
      }
    }
  }

  private func finishTimedOut() {
    storage.withValue { state in
      guard state.lifecycle.phase == .finishing else { return }
      for resource in AudioCaptureLifecycleEvent.Resource.allCases
      where state.pendingStops.contains(resource) {
        dependencies.lifecycle(.resourceTimedOut(resource))
      }
      state.speech?.cancel()
      state.lifecycle.recordFinalizationNotice(
        SessionFailure(
          category: .finalization,
          message: String(
            localized: "Saved the available transcript; audio finalization timed out.")))
      deliverFinish()
    }
  }

  private func deliverFinish() {
    storage.withValue { state in
      guard state.lifecycle.phase == .finishing else { return }
      var audioURL: URL?
      do { audioURL = try state.writer?.finish() } catch {
        let message = String(localized: "Audio could not be saved: \(error.localizedDescription)")
        let failure = SessionFailure(category: .recordingSave, message: message)
        state.lifecycle.recordRecordingFailure(failure)
        dependencies.lifecycle(.failed(failure))
        fputs("\(message)\n", stderr)
      }
      var result = AudioCaptureResult(
        transcript: state.speech?.text ?? "", recordingURL: audioURL,
        duration: state.lifecycle.elapsed(at: dependencies.now()),
        failure: state.lifecycle.failure ?? state.transcriptionFailure)
      result.speakerDetectionNotice = state.speakerDetectionNotice
      result.segments = state.speech?.segments ?? []
      if result.segments.contains(where: { $0.automaticSpeakerName != nil }) {
        result.originalTranscript = state.speech?.originalText
      }
      state.lifecycle.completeFinishing()
      state.result = result
      dependencies.lifecycle(.finished)
      state.deadline?.cancel()
      state.deadline = nil
      state.writer = nil
      state.speech = nil
      state.microphone = nil
      state.application = nil
      let completions = state.finishCompletions
      state.finishCompletions.removeAll()
      for completion in completions { completion(result) }
      state.finalizationOwner = nil
    }
  }
}
