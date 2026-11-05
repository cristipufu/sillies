import Foundation

/// Host-clock timestamps retain the acoustic wait and capture delay before UI delivery.
package struct VoiceEndpointTiming: Sendable {
  package let lastSpeechSample: TimeInterval
  package let detected: TimeInterval

  package init?(lastSpeechSample: TimeInterval, detected: TimeInterval) {
    guard lastSpeechSample.isFinite, detected.isFinite, lastSpeechSample >= 0,
      detected >= lastSpeechSample
    else { return nil }
    self.lastSpeechSample = lastSpeechSample
    self.detected = detected
  }
}
