import AVFoundation
import Foundation
import Synchronization

/// One consumer task per source. Audio callbacks never create tasks or invoke inference.
package final class WindowSpeechChannel: LocalSpeechChannel {
  private enum Phase { case running, finishing, failing, stopped }
  // AVAudioConverter is used exclusively under the input lock; PCM buffers never escape it.
  private struct State: @unchecked Sendable {
    let converter: SpeechBufferConverter
    var buffer = SpeechWindowBuffer()
    var phase = Phase.running
    var completions: [@Sendable () -> Void] = []
    var worker: Task<Void, Never>?
  }
  private let state: Mutex<State>
  private let signal: AsyncStream<Void>.Continuation
  private let request: SpeechChannelRequest

  deinit {
    signal.finish()
    state.withLock { $0.worker?.cancel() }
  }

  package init(engine: any SpeechWindowEngine, request: SpeechChannelRequest) throws {
    guard
      let format = AVAudioFormat(
        standardFormatWithSampleRate: SpeechWindowBuffer.sampleRate, channels: 1)
    else {
      throw SpeechError.unavailable("Could not prepare transcription audio.")
    }
    state = Mutex(State(converter: SpeechBufferConverter(format: format)))
    self.request = request
    let (events, signal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    self.signal = signal
    let priority: TaskPriority =
      request.context.priority == .interactive ? .userInitiated : .utility
    let task = Task.detached(priority: priority) { [weak self] in
      var transcript = SpeechWindowTranscript()
      for await _ in events {
        guard let self else { return }
        do {
          while let window = self.nextWindow() {
            try Task.checkCancellation()
            let result = try await engine.transcribe(
              .init(samples: window.samples, language: request.language, context: request.context))
            try Task.checkCancellation()
            let update = transcript.receive(result, window: window)
            guard self.retire(window, through: update.retiredThrough) else { return }
            for phrase in update.phrases { request.output(phrase) }
          }
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
    state.withLock { $0.worker = task }
  }

  package func append(_ buffer: AVAudioPCMBuffer) {
    do {
      try state.withLock { state in
        guard state.phase == .running else { return }
        guard
          Double(buffer.frameLength) / buffer.format.sampleRate
            <= SpeechWindowBuffer.maximumBufferedDuration
        else { throw SpeechError.overloaded }
        let converted = try state.converter.convert(buffer)
        guard let samples = converted.floatChannelData?[0] else { return }
        try state.buffer.append(
          Array(UnsafeBufferPointer(start: samples, count: Int(converted.frameLength))))
      }
      signal.yield(())
    } catch { fail(error) }
  }

  package func finish(completion: @escaping @Sendable () -> Void) {
    let finished = state.withLock { state in
      guard state.phase != .stopped else { return true }
      state.completions.append(completion)
      if state.phase == .running { state.phase = .finishing }
      return false
    }
    if finished { completion() } else { signal.yield(()) }
  }

  package func cancel() {
    let callbacks = state.withLock { state in
      state.phase = .stopped
      state.buffer.clear()
      state.worker?.cancel()
      state.worker = nil
      let completions = state.completions
      state.completions.removeAll()
      return completions
    }
    signal.finish()
    for callback in callbacks { callback() }
  }

  private func nextWindow() -> SpeechWindowBuffer.Window? {
    state.withLock { state in
      guard state.phase == .running || state.phase == .finishing else { return nil }
      return state.buffer.next(mode: state.phase == .finishing ? .draining : .live)
    }
  }

  private func retire(_ window: SpeechWindowBuffer.Window, through boundary: TimeInterval) -> Bool {
    state.withLock { state in
      guard state.phase == .running || state.phase == .finishing else { return false }
      state.buffer.retire(window, through: boundary)
      return true
    }
  }

  private func completeIfDrained() -> Bool {
    let finished = state.withLock { $0.phase == .finishing && $0.buffer.samples.isEmpty }
    if finished { cancel() }
    return finished
  }

  private func fail(_ error: Error) {
    let notify = state.withLock { state in
      guard state.phase == .running || state.phase == .finishing else { return false }
      state.phase = .failing
      return true
    }
    guard notify else { return }
    request.failure(error.localizedDescription)
    cancel()
  }
}
