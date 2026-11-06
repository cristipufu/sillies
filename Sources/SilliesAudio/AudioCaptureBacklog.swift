import Foundation

/// Numeric diagnostics only. No audio, transcript, application title or device identifier.
package struct AudioCaptureBacklog: Sendable {
  package enum Limit: Sendable { case bytes, callbacks, duration }
  package struct Pressure: Sendable {
    package let limit: Limit
    package let packets: Int
    package let bytes: Int
    package let sourceDuration: TimeInterval
  }
  package struct Timing: Sendable {
    package private(set) var maximumQueueWait: TimeInterval = 0
    package private(set) var maximumProcessing: TimeInterval = 0
    mutating func record(capturedAt: TimeInterval, began: TimeInterval, ended: TimeInterval) {
      maximumQueueWait = max(maximumQueueWait, began - capturedAt)
      maximumProcessing = max(maximumProcessing, ended - began)
    }
  }
  package let pressure: Pressure
  package let timing: Timing
}
