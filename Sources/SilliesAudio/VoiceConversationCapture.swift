import AVFoundation
import Foundation
import SilliesCore
import SilliesSpeech

/// Continuous microphone/AEC/VAD, with short-lived recognizer turns. All device/DSP state is queue-confined.
package final class VoiceConversationCapture: ConversationCapture {
  private static let preRollFrames = 40
  private static let publicationInterval: TimeInterval = 0.1
  private static let maximumTurnDuration: TimeInterval = 120
  private static let maximumDrainingTurns = 8
  private final class State {
    var started = false
    var stopped = false
    var microphone: (any MicrophoneCapture)?
    var processor: ConversationAudioProcessor?
    var turn: ConversationSpeechTurn?
    var turnID = UUID()
    var preRoll: [AVAudioPCMBuffer] = []
    var preview = ""
    var lastPublication: TimeInterval = 0
    var speechStart: TimeInterval?
    var nextSequence = 0
    var turnSequence = 0
    var draining: [Int: ConversationSpeechTurn] = [:]
    var stoppedTurn: AudioCaptureResult?
    var stoppingSequence: Int?
    var failure: SessionFailure?
    var startTime: TimeInterval?
    var stopDeadline: DispatchWorkItem?
    var microphoneStopped = false
    var finishWaiters: [@Sendable (AudioCaptureResult) -> Void] = []
    var finalResult: AudioCaptureResult?
  }
  private let configuration: AudioCaptureConfiguration
  private let reference: VoicePlaybackReference
  private let dependencies: AudioCaptureDependencies
  private let update: @Sendable (AudioCaptureUpdate) -> Void
  private let input: AudioCaptureInputQueue
  private let storage: SerialQueueStorage<State>
  private let preparation = CapturePreparation()

  package convenience init(
    configuration: AudioCaptureConfiguration, reference: VoicePlaybackReference,
    speech: @escaping LocalSpeechFactory.Make,
    update: @escaping @Sendable (AudioCaptureUpdate) -> Void
  ) {
    self.init(
      configuration: configuration, reference: reference,
      dependencies: .init(speech: speech), update: update)
  }
  init(
    configuration: AudioCaptureConfiguration, reference: VoicePlaybackReference,
    dependencies: AudioCaptureDependencies, update: @escaping @Sendable (AudioCaptureUpdate) -> Void
  ) {
    self.configuration = configuration
    self.reference = reference
    self.dependencies = dependencies
    self.update = update
    input = AudioCaptureInputQueue(queue: dependencies.queue)
    storage = SerialQueueStorage(queue: dependencies.queue, makeValue: State.init)
  }

  package func start() {
    dependencies.queue.async { [self] in
      storage.withValue { state in
        guard !state.started, !state.stopped else { return }
        state.started = true
        do {
          reference.start()
          state.processor = try ConversationAudioProcessor(reference: reference)
          state.microphone = dependencies.microphone(
            { [weak self] packet in
              self?.enqueue(packet)
            }, { [weak self] failure in self?.report(failure) })
          update(.preparing(String(localized: "Getting voice conversation ready…")))
          // Warm the first recognizer before opening the microphone. Later turns reuse the warm runtime.
          try beginTurn(state) { [weak self] in self?.startMicrophone() }
        } catch { report(SessionFailure(error, category: .audioProcessing)) }
      }
    }
  }

  private func startMicrophone() {
    guard let microphone = storage.withValue({ $0.stopped ? nil : $0.microphone }) else { return }
    preparation.launch { [weak self] in
      do {
        let label = try await microphone.start()
        try Task.checkCancellation()
        self?.dependencies.queue.async { [weak self] in
          guard let self, !self.storage.withValue({ $0.stopped }) else { return }
          self.update(.capturing(label))
        }
      } catch {
        if !Task.isCancelled { self?.report(SessionFailure(error, category: .captureUnavailable)) }
      }
    }
  }

  private func enqueue(_ packet: AudioCaptureInputQueue.Packet) {
    input.enqueue(
      packet, receive: { [weak self] in self?.process($0) },
      overflow: { [weak self] in
        self?.report(
          .init(
            category: .audioProcessing,
            message:
              String(
                localized:
                  "Voice conversation could not keep up with the microphone. Please start it again."
              )))
      })
  }

  private func process(_ packet: AudioCaptureInputQueue.Packet) {
    storage.withValue { state in
      guard !state.stopped, let processor = state.processor else { return }
      do {
        try processor.append(packet)
        while let (buffer, event, time) = try processor.next() {
          if state.startTime == nil { state.startTime = time }
          state.preRoll.append(buffer)
          if state.preRoll.count > Self.preRollFrames { state.preRoll.removeFirst() }
          if event == .began {
            state.speechStart = time
            update(.speechStarted)
            if state.turn == nil { try beginTurn(state) }
            for preceding in state.preRoll.dropLast() { state.turn?.append(preceding) }
          }
          if state.speechStart != nil { state.turn?.append(buffer) }
          if event == .ended
            || state.speechStart.map({ time - $0 >= Self.maximumTurnDuration }) == true
          {
            state.speechStart = nil
            update(.speechEnded)
          }
          if time - state.lastPublication >= Self.publicationInterval {
            state.lastPublication = time
            update(
              .transcript(
                state.preview, level: AudioPCMTools.level(buffer),
                elapsed: time - (state.startTime ?? time)))
          }
        }
      } catch { report(SessionFailure(error, category: .audioProcessing)) }
    }
  }

  private func beginTurn(_ state: State, ready: @escaping @Sendable () -> Void = {}) throws {
    guard state.draining.count < Self.maximumDrainingTurns else {
      throw AudioCaptureFailure.unavailable(
        String(
          localized:
            "Speech recognition could not keep up. Your available words are kept; please start voice again."
        )
      )
    }
    guard let language = configuration.language else {
      throw AudioCaptureFailure.unavailable(
        String(localized: "Choose a speech language before starting Chat."))
    }
    let id = UUID()
    state.turnSequence = state.nextSequence
    state.nextSequence += 1
    state.turnID = id
    state.preview = ""
    let turn = ConversationSpeechTurn(
      queue: dependencies.queue,
      configuration: .init(
        dictionary: configuration.dictionary, finalizationTimeout: dependencies.finishTimeout),
      changed: { [weak self] text in
        self?.storage.withValue { state in
          if !state.stopped, state.turnID == id { state.preview = text }
        }
      }, failed: { [weak self] in self?.report($0) })
    state.turn = turn
    turn.prepare(language: language, make: dependencies.speech, ready: ready)
  }

  package func finishTurn(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    dependencies.queue.async { [self] in
      storage.withValue { state in
        guard !state.stopped else {
          completion(.init(transcript: "", recordingURL: nil, duration: 0, failure: nil))
          return
        }
        flushPendingAudio(state)
        state.speechStart = nil
        state.processor?.beginNextTurn()
        drainTurn(completion)
      }
    }
  }
  private func drainTurn(_ completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    storage.withValue { state in
      let turn = state.turn
      let sequence = state.turnSequence
      state.turn = nil
      state.turnID = UUID()
      state.preRoll.removeAll()
      state.preview = ""
      if let turn {
        state.draining[sequence] = turn
        turn.finish { [self] result in
          storage.withValue { state in
            state.draining.removeValue(forKey: sequence)
            if state.stoppingSequence == sequence { state.stoppedTurn = result }
          }
          completion(result)
          completeStopIfReady()
        }
      } else {
        completion(.init(transcript: "", recordingURL: nil, duration: 0, failure: nil))
      }
    }
  }

  package func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    input.stop()
    preparation.cancel()
    dependencies.queue.async { [self] in
      storage.withValue { state in
        if let result = state.finalResult {
          completion(result)
          return
        }
        state.finishWaiters.append(completion)
        guard !state.stopped else {
          completeStopIfReady()
          return
        }
        state.stopped = true
        reference.stop()
        flushPendingAudio(state)
        state.processor = nil
        let microphone = state.microphone
        state.microphone = nil
        state.stoppingSequence = state.turn == nil ? nil : state.turnSequence
        drainTurn { _ in }
        if let microphone {
          scheduleStopDeadline(state)
          microphone.stop { [self] in
            dependencies.queue.async { [self] in
              storage.withValue { $0.microphoneStopped = true }
              completeStopIfReady()
            }
          }
        } else {
          state.microphoneStopped = true
          completeStopIfReady()
        }
      }
    }
  }
  private func completeStopIfReady() {
    storage.withValue { state in
      guard state.stopped, state.microphoneStopped, state.draining.isEmpty, state.finalResult == nil
      else { return }
      let turn = state.stoppedTurn
      var result = AudioCaptureResult(
        transcript: turn?.transcript ?? "",
        recordingURL: nil, duration: turn?.duration ?? 0,
        failure: state.failure ?? turn?.failure)
      result.segments = turn?.segments ?? []
      state.finalResult = result
      state.stoppedTurn = nil
      state.stopDeadline?.cancel()
      state.stopDeadline = nil
      let waiters = state.finishWaiters
      state.finishWaiters.removeAll()
      for waiter in waiters { waiter(result) }
    }
  }

  private func report(_ failure: SessionFailure) {
    dependencies.queue.async { [self] in
      guard !storage.withValue({ $0.stopped }) else { return }
      storage.withValue { $0.failure = failure }
      update(.failed(failure))
      finish { _ in }
    }
  }

  private func flushPendingAudio(_ state: State) {
    guard let processor = state.processor, let turn = state.turn else { return }
    do {
      while let buffer = try processor.nextFinalMicrophone() { turn.append(buffer) }
    } catch {
      state.failure = SessionFailure(error, category: .audioProcessing)
    }
  }

  private func scheduleStopDeadline(_ state: State) {
    let deadline = DispatchWorkItem { [self] in
      storage.withValue { state in
        guard !state.microphoneStopped else { return }
        state.microphoneStopped = true
        state.failure =
          state.failure
          ?? .init(
            category: .finalization,
            message: String(
              localized: "The microphone took too long to stop. Your available words are kept."))
      }
      completeStopIfReady()
    }
    state.stopDeadline = deadline
    dependencies.queue.asyncAfter(deadline: .now() + dependencies.finishTimeout, execute: deadline)
  }
}
