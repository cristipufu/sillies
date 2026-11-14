import Foundation
import SilliesCore

/// Providers describe qualified decoder behavior; the shared channel owns acoustic decisions and state.
package struct SpeechWindowConfiguration: Sendable {
  package static let sampleRate: Double = 16_000
  package static let maximumWindowDuration: TimeInterval = 12
  package static let maximumSampleCount = Int(sampleRate * maximumWindowDuration)
  package static let leadingContext: TimeInterval = 0.2
  package let cadence: SpeechDecodeCadence
  package let continuousBoundaryMode: SpeechBoundaryPolicy.Mode
  package let boundaryReplayDuration: TimeInterval
  package let inputValidation: SpeechInputValidation
  package init(
    cadence: SpeechDecodeCadence = .windowed,
    continuousBoundaryMode: SpeechBoundaryPolicy.Mode = .baseline,
    boundaryReplayDuration: TimeInterval = leadingContext,
    inputValidation: SpeechInputValidation = .unchecked
  ) {
    self.cadence = cadence
    self.continuousBoundaryMode = continuousBoundaryMode
    self.boundaryReplayDuration = boundaryReplayDuration
    self.inputValidation = inputValidation
  }
}
