import Foundation

/// Retains one second of scalar measurements, never PCM. Caller supplies sample-time measurements.
package struct VoiceAcousticWindow {
  package struct Frame {
    package struct Power {
      package let reference: Double
      package let microphone: Double
      package let cleaned: Double
      package init(reference: Double, microphone: Double, cleaned: Double) {
        self.reference = reference
        self.microphone = microphone
        self.cleaned = cleaned
      }
    }
    package let referenceSamples: Int
    package let clippedSamples: Int
    package let power: Power
    package init(referenceSamples: Int, clippedSamples: Int, power: Power) {
      self.referenceSamples = referenceSamples
      self.clippedSamples = clippedSamples
      self.power = power
    }
  }
  private static let maximumFrames = 100
  private static let minimumPower = 1e-12
  private static let maximumNormalizedPower = 1.0
  private var frames: [Frame] = []
  private var cursor = 0
  package init() {}

  package mutating func append(_ frame: Frame) {
    if frames.count < Self.maximumFrames {
      frames.append(frame)
    } else {
      frames[cursor] = frame
    }
    cursor = (cursor + 1) % Self.maximumFrames
  }

  package var snapshot: VoiceAcousticEvidence.Window {
    var result = VoiceAcousticEvidence.Window()
    result.samples = frames.count * MeetingAudioTimeline.frameSamples
    result.referenceSamples = frames.reduce(0) {
      $0 + min(MeetingAudioTimeline.frameSamples, max(0, $1.referenceSamples))
    }
    result.clippedSamples = frames.reduce(0) {
      $0 + min(MeetingAudioTimeline.frameSamples, max(0, $1.clippedSamples))
    }
    result.referenceDecibels = decibels(\.reference)
    result.microphoneDecibels = decibels(\.microphone)
    result.cleanedDecibels = decibels(\.cleaned)
    return result
  }

  private func decibels(_ key: KeyPath<Frame.Power, Double>) -> Double {
    guard !frames.isEmpty else { return 10 * log10(Self.minimumPower) }
    let power =
      frames.reduce(0.0) { total, frame in
        let value = frame.power[keyPath: key]
        return total + (value.isFinite ? min(Self.maximumNormalizedPower, max(0, value)) : 0)
      } / Double(frames.count)
    return 10 * log10(max(Self.minimumPower, power))
  }
}
