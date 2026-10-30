import CoreMedia
import Foundation
import SilliesCore
import Synchronization

/// Retains capture buffers only until the serial processing queue consumes them.
final class AudioCaptureInputQueue: Sendable {
  typealias Receiver = @Sendable (Packet) -> Void

  /// The capture producer relinquishes mutation of this retained sample at enqueue.
  struct Packet: @unchecked Sendable {
    let sample: CMSampleBuffer
    let source: SessionAudioSource
    let duration: TimeInterval
    let capturedAt: TimeInterval
    let sampleStartTime: TimeInterval

    init?(sample: CMSampleBuffer, source: SessionAudioSource, sourceClock: CMClock? = nil) {
      guard let description = sample.formatDescription,
        let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)
      else { return nil }
      self.sample = sample
      self.source = source
      duration = Double(sample.numSamples) / format.pointee.mSampleRate
      capturedAt = AudioCaptureClock.now
      let presentationTime =
        sourceClock.map {
          CMSyncConvertTime(sample.presentationTimeStamp, from: $0, to: CMClockGetHostTimeClock())
            .seconds
        } ?? sample.presentationTimeStamp.seconds
      sampleStartTime =
        presentationTime.isFinite && presentationTime > 0
        ? presentationTime : capturedAt - duration
    }
  }
  static let maximumQueuedBytes = 32 * 1_024 * 1_024

  struct Metrics: Sendable {
    var pendingPackets = 0
    var retainedBytes = 0
    var peakRetainedBytes = 0
  }
  private struct State {
    var budget = AudioInputBudget<SessionAudioSource>()
    var accepting = true
    var metrics = Metrics()
  }
  private let queue: DispatchQueue
  private let state = Mutex(State())

  init(queue: DispatchQueue) { self.queue = queue }

  var metrics: Metrics { state.withLock { $0.metrics } }

  func enqueue(
    _ packet: Packet, receive: @escaping Receiver,
    overflow: @escaping @Sendable () -> Void
  ) {
    let bytes = packet.sample.dataBuffer?.dataLength ?? packet.sample.totalSampleSize
    state.withLock { state in
      guard state.accepting else { return }
      guard bytes <= Self.maximumQueuedBytes - state.metrics.retainedBytes else {
        state.accepting = false
        queue.async(execute: overflow)
        return
      }
      switch state.budget.reserve(duration: packet.duration, source: packet.source) {
      case .invalid: return
      case .full:
        state.accepting = false
        queue.async(execute: overflow)
      case .accepted:
        state.metrics.pendingPackets += 1
        state.metrics.retainedBytes += bytes
        state.metrics.peakRetainedBytes = max(
          state.metrics.peakRetainedBytes, state.metrics.retainedBytes)
        // Admission and submission are atomic with stop, so finish cannot overtake this buffer.
        queue.async { [self] in
          defer { release(packet, bytes: bytes) }
          receive(packet)
        }
      }
    }
  }

  private func release(_ packet: Packet, bytes: Int) {
    state.withLock {
      $0.budget.release(duration: packet.duration, source: packet.source)
      $0.metrics.pendingPackets -= 1
      $0.metrics.retainedBytes -= bytes
    }
  }

  /// Previously admitted buffers drain in order before the session's finish operation.
  func stop() { state.withLock { $0.accepting = false } }
}
