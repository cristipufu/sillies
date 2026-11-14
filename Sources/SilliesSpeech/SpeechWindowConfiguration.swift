import SilliesCore

/// Providers describe qualified decoder behavior; the shared channel owns acoustic decisions and state.
package struct SpeechWindowConfiguration: Sendable {
  package let cadence: SpeechDecodeCadence
  package let continuousBoundaryMode: SpeechBoundaryPolicy.Mode
  package init(
    cadence: SpeechDecodeCadence = .windowed,
    continuousBoundaryMode: SpeechBoundaryPolicy.Mode = .baseline
  ) {
    self.cadence = cadence
    self.continuousBoundaryMode = continuousBoundaryMode
  }
}
