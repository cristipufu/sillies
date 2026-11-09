import Foundation

/// An injected session-owned backlog. Implementations must bound storage and perform I/O off main.
package protocol SpeechAudioBackingStore: Sendable {
  var endSample: Int64 { get }
  func append(_ samples: [Float]) throws
  func read(from sample: Int64, maximumSamples: Int) throws -> [Float]
  func retire(before sample: Int64) throws
  func close() throws
}

package struct SpeechRecoveryUpdate: Sendable {
  package enum Phase: Sendable, Equatable { case retrying, catchingUp, caughtUp, stopped }
  package let channel: UUID
  package let phase: Phase
  package let queuedSeconds: Double
  package init(channel: UUID, phase: Phase, queuedSeconds: Double) {
    self.channel = channel
    self.phase = phase
    self.queuedSeconds = queuedSeconds
  }
}
