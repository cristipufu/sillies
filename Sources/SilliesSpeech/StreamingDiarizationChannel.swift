import AVFoundation
import Foundation
import Synchronization

/// PCM admission is bounded; one worker drains it without retaining the session's audio.
package final class StreamingDiarizationChannel: LocalSpeechChannel {
  private static let sampleRate: Double = 16_000
  private static let maximumBufferedSeconds: Double = 16
  private static let processingSeconds: Double = 1
  private static let overloadMessage =
    "Speaker detection could not keep pace. Transcription continues without speaker labels."
  private enum Phase { case receiving, draining, failing, stopped }
  // Converter access is confined to the input lock. No native buffers escape it.
  private struct State: @unchecked Sendable {
    let converter: SpeechBufferConverter
    var samples: [Float] = []
    var phase = Phase.receiving
    var completions: [@Sendable () -> Void] = []
    var worker: Task<Void, Never>?
  }
  private let input: Mutex<State>
  private let signal: AsyncStream<Void>.Continuation
  private let request: SpeakerDiarizationRequest

  package init(engine: any SpeakerDiarizationEngine, request: SpeakerDiarizationRequest) throws {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)
    else {
      throw SpeechError.unavailable("Could not prepare speaker detection audio.")
    }
    self.request = request
    input = Mutex(State(converter: SpeechBufferConverter(format: format)))
    let (events, signal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    self.signal = signal
    let worker = Task.detached(priority: .utility) { [weak self] in
      for await _ in events {
        guard let self else { return }
        do {
          while let samples = self.nextSamples() {
            try Task.checkCancellation()
            self.publish(try await engine.append(samples))
          }
          if self.input.withLock({ $0.phase == .draining && $0.samples.isEmpty }) {
            self.publish(try await engine.finish())
            self.cancel()
            return
          }
        } catch is CancellationError {
          self.cancel()
          return
        } catch {
          self.fail(error)
          return
        }
      }
    }
    input.withLock { $0.worker = worker }
  }

  deinit {
    signal.finish()
    input.withLock { $0.worker?.cancel() }
  }

  package func append(_ buffer: AVAudioPCMBuffer) {
    do {
      try input.withLock { state in
        guard state.phase == .receiving else { return }
        guard Double(buffer.frameLength) / buffer.format.sampleRate <= Self.maximumBufferedSeconds
        else {
          throw SpeechError.unavailable(Self.overloadMessage)
        }
        let converted = try state.converter.convert(buffer)
        let count = Int(converted.frameLength)
        guard state.samples.count + count <= Int(Self.maximumBufferedSeconds * Self.sampleRate)
        else {
          throw SpeechError.unavailable(Self.overloadMessage)
        }
        if let samples = converted.floatChannelData?[0] {
          state.samples.append(contentsOf: UnsafeBufferPointer(start: samples, count: count))
        }
      }
      signal.yield(())
    } catch { fail(error) }
  }

  package func finish(completion: @escaping @Sendable () -> Void) {
    let stopped = input.withLock { state in
      guard state.phase != .stopped else { return true }
      state.completions.append(completion)
      if state.phase == .receiving { state.phase = .draining }
      return false
    }
    if stopped { completion() } else { signal.yield(()) }
  }

  package func cancel() {
    let completions = input.withLock { state in
      state.phase = .stopped
      state.samples.removeAll()
      state.worker?.cancel()
      state.worker = nil
      defer { state.completions.removeAll() }
      return state.completions
    }
    signal.finish()
    for completion in completions { completion() }
  }

  private func nextSamples() -> [Float]? {
    input.withLock { state in
      guard state.phase == .receiving || state.phase == .draining, !state.samples.isEmpty else {
        return nil
      }
      let count = min(state.samples.count, Int(Self.processingSeconds * Self.sampleRate))
      let samples = Array(state.samples.prefix(count))
      state.samples.removeFirst(count)
      return samples
    }
  }

  private func publish(_ batches: [SpeakerActivityBatch]) {
    guard !Task.isCancelled, input.withLock({ $0.phase == .receiving || $0.phase == .draining })
    else { return }
    for batch in batches { request.output(batch) }
  }

  private func fail(_ error: Error) {
    let notify = input.withLock { state in
      guard state.phase == .receiving || state.phase == .draining else { return false }
      state.phase = .failing
      return true
    }
    guard notify else { return }
    request.failure(error.localizedDescription)
    cancel()
  }
}
