import CoreMedia
import Foundation
import SilliesCore

/// Retains capture buffers only until the serial processing queue consumes them.
final class AudioCaptureInputQueue: @unchecked Sendable {
  struct Packet: @unchecked Sendable {
    let sample: CMSampleBuffer
    let source: SessionAudioSource
    let duration: TimeInterval
    let capturedAt: TimeInterval

    init?(sample: CMSampleBuffer, source: SessionAudioSource) {
      guard let description = sample.formatDescription,
        let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)
      else { return nil }
      self.sample = sample
      self.source = source
      duration = Double(sample.numSamples) / format.pointee.mSampleRate
      capturedAt = ProcessInfo.processInfo.systemUptime
    }
  }
  private let queue: DispatchQueue
  private let lock = NSLock()
  private var budget = AudioInputBudget<SessionAudioSource>()
  private var accepting = true

  init(queue: DispatchQueue) { self.queue = queue }

  func enqueue(
    _ packet: Packet, receive: @escaping @Sendable (Packet) -> Void,
    overflow: @escaping @Sendable () -> Void
  ) {
    lock.withLock {
      guard accepting else { return }
      switch budget.reserve(duration: packet.duration, source: packet.source) {
      case .invalid: return
      case .full:
        accepting = false
        queue.async(execute: overflow)
      case .accepted:
        // Admission and submission are atomic with stop, so finish cannot overtake this buffer.
        queue.async { [self] in
          defer {
            lock.withLock { budget.release(duration: packet.duration, source: packet.source) }
          }
          receive(packet)
        }
      }
    }
  }

  /// Previously admitted buffers drain in order before the session's finish operation.
  func stop() { lock.withLock { accepting = false } }
}
