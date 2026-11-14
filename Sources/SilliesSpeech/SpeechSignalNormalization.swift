import Foundation
import SilliesCore

/// Validates a complete retained window before returning one immutable adjustment for its new samples.
package struct SpeechSignalNormalization: Sendable {
  package enum Mode: String, Codable, Sendable { case preserve, bounded }
  package struct Adjustment: Sendable {
    package let gain: Float
    package func apply(to samples: [Float]) -> [Float] {
      gain == 1 ? samples : samples.map { $0 * gain }
    }
  }
  private var level: SpeechSignalGain
  private let mode: Mode
  package init(mode: Mode = .bounded, gain: SpeechSignalGain = .init()) {
    self.mode = mode
    self.level = gain
  }

  package mutating func prepare(_ samples: [Float]) throws -> Adjustment {
    var peak: Float = 0
    var sumSquares = 0.0
    for sample in samples {
      guard sample.isFinite else { throw SpeechError.invalidAudioFormat }
      peak = max(peak, abs(sample))
      let value = Double(sample)
      sumSquares += value * value
    }
    let rootMeanSquare = Float((sumSquares / Double(max(1, samples.count))).squareRoot())
    guard
      let gain = mode == .preserve ? 1 : level.observe(peak: peak, rootMeanSquare: rootMeanSquare)
    else {
      throw SpeechError.invalidAudioFormat
    }
    return Adjustment(gain: gain)
  }

  package mutating func reset() { level.reset() }
}
