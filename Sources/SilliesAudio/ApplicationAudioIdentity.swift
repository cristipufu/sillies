import SilliesCore

/// Composition verifies the selected running application without adding AppKit to audio capture.
package enum ApplicationAudioIdentity: Sendable { case verified, ambiguous, unavailable }
package typealias ApplicationAudioIdentityCheck =
  @Sendable (WindowTargetCandidate) -> ApplicationAudioIdentity
