import Foundation
import SilliesCore
import Synchronization

/// Reports the first non-silent output sample's presentation time once per device lifetime.
final class VoiceAudibilityProbe: Sendable {
  private static let minimumAmplitude: Float = 0.001
  private let reported = Mutex(false)
  private let receive: @Sendable (TimeInterval) -> Void
  init(receive: @escaping @Sendable (TimeInterval) -> Void) { self.receive = receive }

  func observe(_ frame: AudioRenderFrame) {
    guard frame.startTime.isFinite, frame.startTime >= 0, frame.sampleRate.isFinite,
      frame.sampleRate > 0,
      !reported.withLock({ $0 }),
      let index = frame.samples.firstIndex(where: {
        $0.isFinite && abs($0) >= Self.minimumAmplitude
      })
    else { return }
    let first = reported.withLock { reported in
      guard !reported else { return false }
      reported = true
      return true
    }
    if first { receive(frame.startTime + Double(index) / frame.sampleRate) }
  }
}
