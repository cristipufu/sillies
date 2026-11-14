import Foundation
import SilliesCore

/// Providers describe qualified decoder behavior; the shared channel owns acoustic decisions and state.
package struct SpeechWindowConfiguration: Sendable {
  package static let leadingContext: TimeInterval = 0.2
  package let cadence: SpeechDecodeCadence
  package let continuousBoundaryMode: SpeechBoundaryPolicy.Mode
  package let boundaryReplayDuration: TimeInterval
  package init(
    cadence: SpeechDecodeCadence = .windowed,
    continuousBoundaryMode: SpeechBoundaryPolicy.Mode = .baseline,
    boundaryReplayDuration: TimeInterval = leadingContext
  ) {
    self.cadence = cadence
    self.continuousBoundaryMode = continuousBoundaryMode
    self.boundaryReplayDuration = boundaryReplayDuration
  }
}
