import Foundation

/// Mono output actually rendered by a device, on the same host clock as captured microphone audio.
public struct AudioRenderFrame: Sendable {
  public let samples: [Float]
  public let sampleRate: Double
  public let startTime: TimeInterval
  public init(samples: [Float], sampleRate: Double, startTime: TimeInterval) {
    self.samples = samples
    self.sampleRate = sampleRate
    self.startTime = startTime
  }
}
