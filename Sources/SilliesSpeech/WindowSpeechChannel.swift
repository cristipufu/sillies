import AVFoundation
import Foundation
import Synchronization

/// One consumer task per source. Audio callbacks never create tasks or invoke inference.
package final class WindowSpeechChannel: LocalSpeechChannel {
  private enum Phase { case running, finishing, failing, stopped }
  private static let readChunkSamples = 1_600
  private static let maximumTransientAttempts = 3
  private static let initialRetryDelay: TimeInterval = 0.1
  private static let maximumRetryDelay: TimeInterval = 4
  private static let maximumRetryExponent = 6
  private let identity = UUID()
  // AVAudioConverter is used exclusively under the input lock; PCM buffers never escape it.
  private struct State: @unchecked Sendable {
    let converter: SpeechBufferConverter
    var buffer = SpeechWindowBuffer()
    var phase = Phase.running
    var completions: [@Sendable () -> Void] = []
    var worker: Task<Void, Never>?
    var readSample: Int64 = 0
    var recoveryPhase: SpeechRecoveryUpdate.Phase?
    var recovery: (@Sendable (SpeechRecoveryUpdate) -> Void)?
  }
  private final class StateOwner: Sendable {
    let value: Mutex<State>
    init(_ state: State) { value = Mutex(state) }
  }
  private let state: StateOwner
  private let signal: AsyncStream<Void>.Continuation
  private let request: SpeechChannelRequest

  deinit {
    signal.finish()
    state.value.withLock { $0.worker?.cancel() }
  }

  package init(
    engine: any SpeechWindowEngine, request: SpeechChannelRequest,
    configuration: SpeechWindowConfiguration = .init()
  ) throws {
    guard
      configuration.boundaryReplayDuration.isFinite, configuration.boundaryReplayDuration >= 0,
      configuration.boundaryReplayDuration <= SpeechWindowBuffer.maximumReplayDuration,
      let format = AVAudioFormat(
        standardFormatWithSampleRate: SpeechWindowBuffer.sampleRate, channels: 1)
    else {
      throw SpeechError.unavailable(String(localized: "Could not prepare transcription audio."))
    }
    var initial = State(converter: SpeechBufferConverter(format: format))
    initial.buffer.cadence = configuration.cadence
    initial.buffer.boundaryReplayDuration = configuration.boundaryReplayDuration
    initial.buffer.boundaries = .init(
      mode: request.context.windowBoundaryMode(for: configuration))
    state = StateOwner(initial)
    self.request = request
    let (events, signal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    self.signal = signal
    let priority = request.context.priority.taskPriority
    let sharedState = state
    let channelIdentity = identity
    let task = Task.detached(priority: priority) { [weak self, sharedState] in
      defer {
        Self.completeWorker(
          sharedState, backingStore: request.audioBackingStore, identity: channelIdentity)
      }
      var transcript = SpeechWindowTranscript()
      var results = SpeechWindowResultCache(policy: engine.finalizationPolicy)
      for await _ in events {
        guard let self else { return }
        do {
          while let window = try self.nextWindow() {
            try Task.checkCancellation()
            request.measureWindow?(
              .init(
                start: window.start, sampleCount: window.samples.count,
                completion: window.completion))
            var input = SpeechWindowRequest(
              samples: window.samples, language: request.language, context: request.context)
            input.window = .init(
              start: window.start, phase: window.completion.inferencePhase)
            let result: SpeechWindowResult
            if let cached = results.result(for: window) {
              result = cached
            } else {
              result = try await self.transcribeRecovering(input, engine: engine)
              results.remember(result, for: window)
            }
            try Task.checkCancellation()
            let update = transcript.receive(result, window: window)
            guard try self.retire(window, through: update.retiredThrough) else { return }
            for phrase in update.phrases { request.output(phrase) }
            self.reportCaughtUp()
          }
          self.reportCaughtUp()
          if self.completeIfDrained() { return }
        } catch is CancellationError {
          self.cancel()
          return
        } catch {
          self.fail(error)
          return
        }
      }
    }
    state.value.withLock { $0.worker = task }
  }

  package func append(_ buffer: AVAudioPCMBuffer) {
    do {
      try state.value.withLock { state in
        guard state.phase == .running else { return }
        guard
          Double(buffer.frameLength) / buffer.format.sampleRate
            <= SpeechWindowBuffer.maximumBufferedDuration
        else { throw SpeechError.overloaded }
        let converted = try state.converter.convert(buffer)
        guard let samples = converted.floatChannelData?[0] else { return }
        let incoming = Array(UnsafeBufferPointer(start: samples, count: Int(converted.frameLength)))
        if let backingStore = request.audioBackingStore {
          try backingStore.append(incoming)
        } else {
          if state.buffer.boundaries.mode == .adaptive {
            try state.buffer.appendAnalysisFrames(incoming)
          } else {
            try state.buffer.append(incoming)
          }
        }
      }
      reportBacklog()
      signal.yield(())
    } catch { fail(error) }
  }

  package func onRecovery(_ receive: @escaping @Sendable (SpeechRecoveryUpdate) -> Void) {
    state.value.withLock { $0.recovery = receive }
  }

  package func finish(completion: @escaping @Sendable () -> Void) {
    let finished = state.value.withLock { state in
      guard state.phase != .stopped || state.worker != nil else { return true }
      state.completions.append(completion)
      if state.phase == .running { state.phase = .finishing }
      return false
    }
    if finished { completion() } else { signal.yield(()) }
  }

  package func cancel() {
    state.value.withLock { state in
      state.phase = .stopped
      state.worker?.cancel()
    }
    signal.finish()
  }

  private func nextWindow() throws -> SpeechWindowBuffer.Window? {
    try state.value.withLock { state in
      guard state.phase == .running || state.phase == .finishing else { return nil }
      if let backingStore = request.audioBackingStore {
        let pending = backingStore.endSample - state.buffer.retainedStartSample
        let mode: SpeechWindowBuffer.Mode =
          pending >= Int64(SpeechWindowBuffer.maximumWindowDuration * SpeechWindowBuffer.sampleRate)
          ? .catchingUp : .live
        if let ready = state.buffer.next(mode: mode) { return ready }
        while state.readSample < backingStore.endSample {
          let samples = try backingStore.read(
            from: state.readSample, maximumSamples: Self.readChunkSamples)
          guard !samples.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
          try state.buffer.appendAnalysisFrames(samples)
          state.readSample += Int64(samples.count)
          if let ready = state.buffer.next(mode: mode) { return ready }
          try backingStore.retire(before: state.buffer.retainedStartSample)
        }
      }
      return state.buffer.next(mode: state.phase == .finishing ? .draining : .live)
    }
  }

  private func retire(_ window: SpeechWindowBuffer.Window, through boundary: TimeInterval) throws
    -> Bool
  {
    try state.value.withLock { state in
      guard state.phase == .running || state.phase == .finishing else { return false }
      state.buffer.retire(window, through: boundary)
      try request.audioBackingStore?.retire(before: state.buffer.retainedStartSample)
      return true
    }
  }

  private func completeIfDrained() -> Bool {
    state.value.withLock {
      $0.phase == .stopped
        || ($0.phase == .finishing && $0.buffer.samples.isEmpty
          && $0.readSample >= (request.audioBackingStore?.endSample ?? 0))
    }
  }

  private func fail(_ error: Error) {
    let notify = state.value.withLock { state in
      guard state.phase == .running || state.phase == .finishing else { return false }
      state.phase = .failing
      return true
    }
    guard notify else { return }
    request.failure(error.localizedDescription)
    cancel()
  }

  private func transcribeRecovering(_ input: SpeechWindowRequest, engine: any SpeechWindowEngine)
    async throws -> SpeechWindowResult
  {
    var attempts = 0
    while true {
      do {
        try Task.checkCancellation()
        request.measureInference?(
          .init(
            start: input.window?.start ?? 0, sampleCount: input.samples.count,
            phase: input.window?.phase ?? .complete))
        return try await engine.transcribe(input)
      } catch is CancellationError { throw CancellationError() } catch {
        attempts = min(attempts + 1, Self.maximumRetryExponent + 1)
        let overloaded: Bool
        if let failure = error as? SpeechError, case .overloaded = failure {
          overloaded = true
        } else {
          overloaded = false
        }
        if !overloaded, attempts >= Self.maximumTransientAttempts { throw error }
        reportRecovery(.retrying)
        let delay = min(
          Self.maximumRetryDelay, Self.initialRetryDelay * pow(2, Double(attempts - 1)))
        try await Task.sleep(for: .seconds(delay))
      }
    }
  }

  private func reportBacklog() {
    let behind = state.value.withLock { state in
      guard let backingStore = request.audioBackingStore else { return false }
      return Double(backingStore.endSample - state.buffer.retainedStartSample)
        / SpeechWindowBuffer.sampleRate
        > SpeechWindowBuffer.maximumWindowDuration
    }
    if behind { reportRecovery(.catchingUp) }
  }

  private func reportCaughtUp() {
    let caughtUp = state.value.withLock { state in
      state.recoveryPhase != nil && state.readSample >= (request.audioBackingStore?.endSample ?? 0)
    }
    if caughtUp { reportRecovery(.caughtUp) }
  }

  private func reportRecovery(_ phase: SpeechRecoveryUpdate.Phase) {
    let delivery = state.value.withLock {
      state -> ((@Sendable (SpeechRecoveryUpdate) -> Void), SpeechRecoveryUpdate)? in
      guard state.phase == .running || state.phase == .finishing,
        state.recoveryPhase != phase, let receive = state.recovery
      else { return nil }
      state.recoveryPhase = phase
      let samples =
        request.audioBackingStore.map { max(0, $0.endSample - state.buffer.retainedStartSample) }
        ?? Int64(state.buffer.samples.count)
      return (
        receive,
        .init(
          channel: identity, phase: phase,
          queuedSeconds: Double(samples) / SpeechWindowBuffer.sampleRate)
      )
    }
    if let (receive, update) = delivery { receive(update) }
  }

  private static func completeWorker(
    _ state: StateOwner, backingStore: (any SpeechAudioBackingStore)?, identity: UUID
  ) {
    do { try backingStore?.close() } catch {
      fputs("Transcription backlog cleanup failed.\n", stderr)
    }
    let callbacks = state.value.withLock { state in
      state.phase = .stopped
      state.worker = nil
      state.buffer.clear()
      let callbacks = state.completions
      state.completions.removeAll()
      let recovery =
        state.recoveryPhase == nil || state.recoveryPhase == .caughtUp ? nil : state.recovery
      return (callbacks, recovery)
    }
    callbacks.1?(.init(channel: identity, phase: .stopped, queuedSeconds: 0))
    for callback in callbacks.0 { callback() }
  }
}
